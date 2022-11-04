/*
Name: dbo.RefreshTimeZoneConversionHelperTable
Purpose: populate the dbo.TimeZoneConversionHelper table
Parameters:
	@FixedStartDate - The earliest date to load into the dbo.TimeZoneConversionHelper table.
					  If this parameter is set then @RangeYearsBack must be NULL.	
	@RangeYearsBack - The number of years to look back for the data range to load into the load into the dbo.TimeZoneConversionHelper table.
					  If this parameter is set then @FixedStartDate must be NULL.	
	@RangeYearsForward - The number of years to look forward for the data range to load into the load into the dbo.TimeZoneConversionHelper table.
	@TimeZoneFilter - Optional table-valued parameter that contains a set of time zone names from sys.time_zone_info.
					  If populated then only those time zones will be loaded into the TimeZoneConversionHelper table.
					  If not populated then all time zones will be loaded into the TimeZoneConversionHelper table.
*/
CREATE OR ALTER PROCEDURE [dbo].[RefreshTimeZoneConversionHelperTable]
(
	@FixedStartDate DATE = NULL,
	@RangeYearsBack SMALLINT = 30,
	@RangeYearsForward SMALLINT = 1,
	@TimeZoneFilter TimeZoneNames READONLY
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE
		@SampleHours TINYINT = 24,
		@RequestedStartYear SMALLINT,
		@RequestedEndYear SMALLINT,
		@PaddedStartDate DATETIME2,
		@PaddedEndDate DATETIME2,
		@SamplePointsNeeded INT,
		@MergeIntervalCount INT;

	IF @RangeYearsBack < 0 OR @RangeYearsForward < 0 OR @RangeYearsForward IS NULL
	BEGIN
		THROW 1569173, N'You can''t do that', 1;
	END;

	IF @FixedStartDate >= GETDATE()
	BEGIN
		THROW 1569173, N'The value for the @FixedStartDate parameter must be before today''s date', 2;
	END;

	IF (@FixedStartDate IS NULL AND @RangeYearsBack IS NULL) OR (@FixedStartDate IS NOT NULL AND @RangeYearsBack IS NOT NULL)
	BEGIN
		THROW 1569173, N'Exactly one of the @FixedStartDate and @RangeYearsBack parameters must be NULL', 3;
	END;
	
	IF EXISTS (SELECT 1 FROM @TimeZoneFilter tz WHERE NOT EXISTS (SELECT 1 FROM sys.time_zone_info tzi WHERE tz.TimeZoneName = tzi.[name]))
	BEGIN
		THROW 1569173, N'All rows in the @TimeZoneFilter parameter must match a row in the sys.time_zone_info catalog view', 4;
	END;
	
	BEGIN TRY
		SET @RequestedStartYear = ISNULL(DATEPART(YEAR, @FixedStartDate), DATEPART(YEAR, GETDATE()) - @RangeYearsBack);
		SET @RequestedEndYear = DATEPART(YEAR, GETDATE()) + @RangeYearsForward;
		SET @PaddedStartDate = DATEADD(HOUR, -24, CAST(ISNULL(@FixedStartDate, DATEFROMPARTS(@RequestedStartYear, 1, 1)) AS DATETIME2));
		SET @PaddedEndDate = DATEADD(HOUR, 48, CAST(DATEFROMPARTS(@RequestedEndYear, 12, 31) AS DATETIME2));
		SET @SamplePointsNeeded = CEILING(1.0 * DATEDIFF(HOUR, @PaddedStartDate, @PaddedEndDate) / @SampleHours);
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH;

	-- as of 2022/11/04 there are no collisions in the catalog view for any collation)
	-- this can only happen if Microsoft releases a new standard time zone name that has a hash collision with an existing one
	IF EXISTS (
		SELECT 1
		FROM sys.time_zone_info
		GROUP BY CHECKSUM([name] COLLATE Latin1_General_100_BIN2)
		HAVING COUNT_BIG(*) > 1
	)
	BEGIN
		THROW 1569173,
N'The helper tables cannot be refreshed due to a checksum collision.
Please open an issue at https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions.
As a workaround, you could update the TZConvert* functions to return FallBackDTO for the new time zone that is causing the issue.
You could also update the TZGetOffset* functions to filter by TimeZoneName instead of by TimeZoneNameChecksum.', 5;
	END;
	

	-- use @TimeZoneFilter if it has at least one row, otherwise get all time zones
	CREATE TABLE #TimeZones (TimeZoneName SYSNAME NOT NULL, TimeZoneChecksum INT NOT NULL, PRIMARY KEY (TimeZoneChecksum)); 

	IF EXISTS (SELECT 1 FROM @TimeZoneFilter)
	BEGIN
		INSERT INTO #TimeZones (TimeZoneName, TimeZoneChecksum)
		SELECT TimeZoneName, CHECKSUM(TimeZoneName COLLATE Latin1_General_100_BIN2)
		FROM @TimeZoneFilter

		UNION

		SELECT N'UTC', CHECKSUM(N'UTC' COLLATE Latin1_General_100_BIN2);
	END
	ELSE
	BEGIN
		INSERT INTO #TimeZones (TimeZoneName, TimeZoneChecksum)
		SELECT [name], CHECKSUM([name] COLLATE Latin1_General_100_BIN2)
		FROM sys.time_zone_info;
	END;


	-- Used later for partition switching so must match TimeZoneConversionHelper_CCI exactly
	-- don't make the data types smaller
	DROP TABLE IF EXISTS dbo.TimeZoneConversionHelper_CCI_For_Switch;
	CREATE TABLE dbo.TimeZoneConversionHelper_CCI_For_Switch (
		[SourceTimeZoneNameChecksum] INT NOT NULL,
		[TargetTimeZoneNameChecksum] INT NOT NULL,
		[YearBucket] [smallint] NOT NULL,
		[IntervalStart] [datetime2](7) NOT NULL,
		[IntervalEnd] [datetime2](7) NOT NULL,
		[OffsetMinutes] [int] NOT NULL,
		[TargetOffsetMinutes] [int] NOT NULL,
		[SourceTimeZoneName] [sysname] NOT NULL,
		[TargetTimeZoneName] [sysname] NOT NULL,
		INDEX CCI_TimeZoneConversionHelper_CCI_For_Switch CLUSTERED COLUMNSTORE
	);

	CREATE TABLE #AllSamplePoints (
		SamplePoint DATETIME2(7) NOT NULL,
		PRIMARY KEY (SamplePoint)
	);


	WITH n10 AS (
		SELECT v.n FROM (
		VALUES  (1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1)
		) v(n)
	),
	n100Mil AS (
		SELECT 1 n
		FROM n10 n1
		CROSS JOIN n10 n2
		CROSS JOIN n10 n3
		CROSS JOIN n10 n4
		CROSS JOIN n10 n5
		CROSS JOIN n10 n6
		CROSS JOIN n10 n7
		CROSS JOIN n10 n8
	)
	INSERT INTO #AllSamplePoints (SamplePoint)
	SELECT c.calc_date
	FROM
	(
		SELECT TOP (@SamplePointsNeeded) -1 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) RN
		FROM n100Mil
	) q
	CROSS APPLY (
		SELECT DATEADD(HOUR, q.RN * @SampleHours, @PaddedStartDate)
	) c (calc_date)
	WHERE c.calc_date > DATEFROMPARTS(DATEPART(YEAR, c.calc_date), 1, 2)
	AND c.calc_date < DATEFROMPARTS(DATEPART(YEAR, c.calc_date), 12, 31)
	OPTION (MAXDOP 1);


	CREATE TABLE #AllCalendarYears (
		DateTruncatedToYear DATETIME2(7) NOT NULL,
		PRIMARY KEY (DateTruncatedToYear)
	);

	INSERT INTO #AllCalendarYears (DateTruncatedToYear)
	SELECT DISTINCT DATEFROMPARTS(DATEPART(YEAR, SamplePoint), 1, 1)   
	FROM #AllSamplePoints

	UNION 

	SELECT DATEFROMPARTS(@RequestedEndYear + 1, 1, 1)

	UNION 

	SELECT DATEFROMPARTS(@RequestedStartYear - 1, 1, 1)

	OPTION (MAXDOP 1);


	-- deal with AT TIME ZONE bug that rarely happens for some time zones around the start of the year
	WITH n49 AS (
		SELECT v.n FROM (
		VALUES  (1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1), (1),
				(1), (1), (1), (1)
		) v(n)
	),
	n49rn AS (
		SELECT -25 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) offset_hours
		FROM n49
	)
	INSERT INTO #AllSamplePoints (SamplePoint)
	SELECT DATEADD(HOUR, n49rn.offset_hours, y.DateTruncatedToYear)
	FROM #AllCalendarYears y
	CROSS JOIN n49rn;


	-- MapType: 0 is UTC -> target, 1 is Source -> UTC
	CREATE TABLE #SampledTimeZoneOffsets (
		MapType TINYINT NOT NULL,
		TimeZoneChecksum INT NOT NULL,
		SamplePoint DATETIME2(7) NOT NULL,
		OffsetMinutes INT NOT NULL,
		PRIMARY KEY (MapType, TimeZoneChecksum, SamplePoint)
	);

	-- must sample map type 0 first due to AT TIME ZONE bug
	INSERT INTO #SampledTimeZoneOffsets (MapType, TimeZoneChecksum, SamplePoint, OffsetMinutes)
	SELECT
		0,
		tz.TimeZoneChecksum,
		cd.SamplePoint,
		o.OffsetMinutes
	FROM #TimeZones tz
	CROSS JOIN #AllSamplePoints cd
	CROSS APPLY (
		SELECT DATEDIFF(MINUTE, cd.SamplePoint, CAST(SWITCHOFFSET(cd.SamplePoint, 0) AT TIME ZONE tz.TimeZoneName AS DATETIME2(7)))
	) o (OffsetMinutes)
	LEFT OUTER JOIN dbo.TimeZoneConversionHelper_CCI_For_Switch z ON 1 = 0 -- allow batch mode
	WHERE tz.TimeZoneName <> N'UTC'
	OPTION (MAXDOP 1, NO_PERFORMANCE_SPOOL);


	CREATE TABLE #TimeZonesWithConstantOffsetToUTC (
		TimeZoneChecksum INT NOT NULL,
		OffsetMinutesFromUTC INT NOT NULL,
		PRIMARY KEY (TimeZoneChecksum)
	);
	
	INSERT INTO #TimeZonesWithConstantOffsetToUTC (TimeZoneChecksum, OffsetMinutesFromUTC)
	SELECT TimeZoneChecksum, MIN(OffsetMinutes)
	FROM #SampledTimeZoneOffsets
	GROUP BY TimeZoneChecksum
	HAVING MIN(OffsetMinutes) = MAX(OffsetMinutes)

	UNION ALL

	SELECT CHECKSUM(N'UTC' COLLATE Latin1_General_100_BIN2), 0
	OPTION (MAXDOP 1);


	INSERT INTO #SampledTimeZoneOffsets (MapType, TimeZoneChecksum, SamplePoint, OffsetMinutes)
	SELECT
		1,
		tz.TimeZoneChecksum,
		cd.SamplePoint,
		o.OffsetMinutes
	FROM #TimeZones tz
	CROSS JOIN #AllSamplePoints cd
	CROSS APPLY (
		SELECT DATEDIFF(MINUTE, cd.SamplePoint, CAST(SWITCHOFFSET(cd.SamplePoint AT TIME ZONE tz.TimeZoneName, 0) AS DATETIME2(7)))
	) o (OffsetMinutes)
	LEFT OUTER JOIN dbo.TimeZoneConversionHelper_CCI_For_Switch z ON 1 = 0 -- allow batch mode
	WHERE NOT EXISTS (
		SELECT 1
		FROM #TimeZonesWithConstantOffsetToUTC t
		WHERE tz.TimeZoneChecksum = t.TimeZoneChecksum
	)
	OPTION (MAXDOP 1, NO_PERFORMANCE_SPOOL);


	CREATE TABLE #IntervalGroups (
		MapType TINYINT NOT NULL,
		TimeZoneChecksum INT NOT NULL,
		TimeZoneName SYSNAME NOT NULL,
		PreviousIntervalEnd DATETIME2(7) NOT NULL,
		IntervalStart DATETIME2(7) NOT NULL,
		PreviousOffsetMinutes INT NOT NULL,
		OffsetMinutes INT NOT NULL
	);

	INSERT INTO #IntervalGroups (MapType, TimeZoneChecksum, TimeZoneName, PreviousIntervalEnd, IntervalStart, PreviousOffsetMinutes, OffsetMinutes)
	SELECT
		MapType,
		tz.TimeZoneChecksum,
		tz.TimeZoneName,
		PreviousSamplePoint,
		SamplePoint,
		PreviousOffsetMinutes,
		OffsetMinutes
	FROM
	(
		SELECT
			MapType,
			TimeZoneChecksum,
			cd.SamplePoint,
			cd.OffsetMinutes,
			LAG(SamplePoint) OVER (PARTITION BY MapType, TimeZoneChecksum ORDER BY SamplePoint) PreviousSamplePoint,
			LAG(cd.OffsetMinutes) OVER (PARTITION BY MapType, TimeZoneChecksum ORDER BY cd.SamplePoint) PreviousOffsetMinutes
			FROM #SampledTimeZoneOffsets cd
			LEFT OUTER JOIN dbo.TimeZoneConversionHelper_CCI_For_Switch z ON 1 = 0 -- allow batch mode
			WHERE NOT EXISTS (
				SELECT 1
				FROM #TimeZonesWithConstantOffsetToUTC t
				WHERE cd.TimeZoneChecksum = t.TimeZoneChecksum
			)
		) q
	INNER JOIN #TimeZones tz ON q.TimeZoneChecksum = tz.TimeZoneChecksum
	WHERE q.OffsetMinutes <> PreviousOffsetMinutes
	OPTION (MAXDOP 1);


	-- reduce gaps in intervals to 1 minute
	SET @MergeIntervalCount = 0;
	WHILE @MergeIntervalCount < CEILING(LOG(@SampleHours * 60) / LOG(2))
	BEGIN
		UPDATE u
		SET
			PreviousIntervalEnd = CASE WHEN PreviousOffsetMinutes = ca2.MidOffsetMinutes THEN ca.MidPoint ELSE PreviousIntervalEnd END,
			IntervalStart = CASE WHEN OffsetMinutes = ca2.MidOffsetMinutes THEN ca.MidPoint ELSE IntervalStart END
		FROM #IntervalGroups u
		CROSS APPLY (
			SELECT DATEADD(MINUTE, CAST(0.5 * DATEDIFF(MINUTE, PreviousIntervalEnd, IntervalStart) AS INT), PreviousIntervalEnd) MidPoint
		) ca
		CROSS APPLY (
			SELECT DATEDIFF(MINUTE, ca.MidPoint, CAST(
				CASE
					WHEN MapType = 0 THEN SWITCHOFFSET(ca.MidPoint, 0) AT TIME ZONE u.TimeZoneName
					WHEN MapType = 1 THEN SWITCHOFFSET(ca.MidPoint AT TIME ZONE u.TimeZoneName, 0)
					END
				 AS DATETIME2(7))
			) MidOffsetMinutes
		) ca2
		WHERE DATEDIFF(MINUTE, PreviousIntervalEnd, IntervalStart) > 1
		OPTION (MAXDOP 1);

		SET @MergeIntervalCount += 1;
	END;

	CREATE TABLE #UTCMapNoBucket (
		MapType TINYINT NOT NULL,
		TimeZoneChecksum INT NOT NULL,		
		IntervalStart DATETIME2(7) NOT NULL,
		IntervalEnd DATETIME2(7) NOT NULL,
		OffsetMinutes INT NOT NULL,
		PRIMARY KEY (MapType, TimeZoneChecksum, IntervalStart)
	);

	INSERT INTO #UTCMapNoBucket (MapType, TimeZoneChecksum, IntervalStart, IntervalEnd, OffsetMinutes)
	SELECT src.MapType, src.TimeZoneChecksum, src.IntervalStart, src.IntervalEnd, src.OffsetMinutes
	FROM (
		SELECT
			MapType,
			TimeZoneChecksum,
			i.IntervalStart,
			ISNULL(LEAD(PreviousIntervalEnd) OVER (PARTITION BY MapType, TimeZoneChecksum ORDER BY i.IntervalStart), @PaddedEndDate) IntervalEnd,		
			i.OffsetMinutes
		FROM #IntervalGroups i
		LEFT OUTER JOIN dbo.TimeZoneConversionHelper_CCI_For_Switch z ON 1 = 0 -- allow batch mode

		UNION ALL

		SELECT MapType, TimeZoneChecksum, @PaddedStartDate, PreviousIntervalEnd, PreviousOffsetMinutes
		FROM (
			SELECT MapType, TimeZoneChecksum, PreviousIntervalEnd, PreviousOffsetMinutes,
			ROW_NUMBER() OVER (PARTITION BY MapType, TimeZoneChecksum ORDER BY IntervalStart) RN
			FROM #IntervalGroups
		) q
		WHERE q.RN = 1
	) src
	OPTION (MAXDOP 1);


	CREATE TABLE #UTCMap (
		MapType TINYINT NOT NULL,
		RelativeYearBucket SMALLINT NOT NULL, -- can be local or UTC
		TimeZoneChecksum INT NOT NULL,	
		UTCIntervalStart DATETIME2(7) NOT NULL,
		UTCIntervalEnd DATETIME2(7) NOT NULL,
		-- these four are only set for target -> UTC
		LocalIntervalStart DATETIME2(7) NULL,
		LocalIntervalEnd DATETIME2(7) NULL,
		UTCYearBucketStart SMALLINT NULL,
		UTCYearBucketEnd SMALLINT NULL,		
		OffsetMinutes INT NOT NULL, -- always set
		INDEX CI CLUSTERED (MapType, RelativeYearBucket)
	);

	INSERT INTO #UTCMap (MapType, TimeZoneChecksum, RelativeYearBucket, UTCIntervalStart, UTCIntervalEnd, 
	LocalIntervalStart, LocalIntervalEnd, UTCYearBucketStart, UTCYearBucketEnd,	OffsetMinutes)
	SELECT 
		MapType,
		TimeZoneChecksum,
		YearBucket,
		CASE WHEN MapType = 0 THEN IntervalStart ELSE ca.UTCIntervalStart END UTCIntervalStart,
		CASE WHEN MapType = 0 THEN IntervalEnd ELSE ca.UTCIntervalEnd END UTCIntervalStart,
		CASE WHEN MapType = 0 THEN NULL ELSE IntervalStart END LocalIntervalStart,
		CASE WHEN MapType = 0 THEN NULL ELSE IntervalEnd END LocalIntervalEnd,
		ca.UTCYearBucketStart,
		ca.UTCYearBucketEnd,
		OffsetMinutes	
	FROM
	(
		SELECT
			MapType,
			TimeZoneChecksum,
			DATEPART(YEAR, FixedIntervals.IntervalStart) YearBucket,
			FixedIntervals.IntervalStart,
			FixedIntervals.IntervalEnd,
			OffsetMinutes
		FROM #UTCMapNoBucket src
		CROSS APPLY (
			SELECT ca1.IntervalPoint IntervalStart, LEAD(ca1.IntervalPoint) OVER (ORDER BY ca1.IntervalPoint) IntervalEnd
			FROM
			(
				SELECT src.IntervalStart IntervalPoint

				UNION ALL

				SELECT src.IntervalEnd

				UNION ALL

				SELECT cy.DateTruncatedToYear
				FROM #AllCalendarYears cy
				WHERE cy.DateTruncatedToYear > src.IntervalStart AND cy.DateTruncatedToYear < src.IntervalEnd
			) ca1
		) FixedIntervals
		WHERE FixedIntervals.IntervalEnd IS NOT NULL

		UNION ALL

		SELECT
			1,
			tz.TimeZoneChecksum,
			DATEPART(YEAR, y.DateTruncatedToYear),
			CASE WHEN y.DateTruncatedToYear > @PaddedStartDate THEN y.DateTruncatedToYear ELSE @PaddedStartDate END,
			CASE WHEN DATEPART(YEAR, y.DateTruncatedToYear) <= @RequestedEndYear THEN DATEADD(YEAR, 1, y.DateTruncatedToYear) ELSE @PaddedEndDate END,
			-1 * tz.OffsetMinutesFromUTC -- reverse for target -> UTC
		FROM #TimeZonesWithConstantOffsetToUTC tz
		CROSS JOIN #AllCalendarYears y
	) q
	OUTER APPLY (
		SELECT		
			DATEPART(YEAR, CAST(SWITCHOFFSET(IntervalStart AT TIME ZONE tz.TimeZoneName, 0) AS DATETIME2(7))) UTCYearBucketStart,
			DATEPART(YEAR, CAST(SWITCHOFFSET(IntervalEnd AT TIME ZONE tz.TimeZoneName, 0) AS DATETIME2(7))) UTCYearBucketEnd,
			SWITCHOFFSET(IntervalStart AT TIME ZONE tz.TimeZoneName, 0) UTCIntervalStart,
			SWITCHOFFSET(IntervalEnd AT TIME ZONE tz.TimeZoneName, 0) UTCIntervalEnd
		FROM #TimeZones tz
		WHERE q.TimeZoneChecksum = tz.TimeZoneChecksum AND MapType = 1
	) ca

	UNION ALL

	SELECT
		0,
		tz.TimeZoneChecksum,
		DATEPART(YEAR, y.DateTruncatedToYear),
		CASE WHEN y.DateTruncatedToYear > @PaddedStartDate THEN y.DateTruncatedToYear ELSE @PaddedStartDate END,
		CASE WHEN DATEPART(YEAR, y.DateTruncatedToYear) <= @RequestedEndYear THEN DATEADD(YEAR, 1, y.DateTruncatedToYear) ELSE @PaddedEndDate END,
		NULL,
		NULL,
		NULL,
		NULL,
		tz.OffsetMinutesFromUTC
	FROM #TimeZonesWithConstantOffsetToUTC tz
	CROSS JOIN #AllCalendarYears y
	OPTION (MAXDOP 1);


	DECLARE @Zero INT = 0;

	INSERT INTO TimeZoneConversionHelper_CCI_For_Switch WITH (TABLOCKX)
	([SourceTimeZoneNameChecksum], [TargetTimeZoneNameChecksum], YearBucket, IntervalStart, IntervalEnd, OffsetMinutes, TargetOffsetMinutes, SourceTimeZoneName, TargetTimeZoneName)
	SELECT
		s.TimeZoneChecksum,
		u.TargetTimeZoneChecksum, 
		s.RelativeYearBucket,
		CASE WHEN s.UTCIntervalStart > u.UTCIntervalStart THEN s.LocalIntervalStart
		ELSE DATEADD(MINUTE, -1 * s.OffsetMinutes, u.UTCIntervalStart) END IntervalStart,
		CASE WHEN s.UTCIntervalEnd < u.UTCIntervalEnd THEN s.LocalIntervalEnd
		ELSE DATEADD(MINUTE, -1 * s.OffsetMinutes, u.UTCIntervalEnd) END IntervalEnd,
		s.OffsetMinutes + u.OffsetMinutes OffsetMinutes,
		u.OffsetMinutes,
		stz.TimeZoneName,
		ttz.TimeZoneName
	FROM #UTCMap s
	CROSS APPLY (
		SELECT
			t.TimeZoneChecksum AS TargetTimeZoneChecksum,
			t.UTCIntervalStart,
			t.UTCIntervalEnd,
			t.OffsetMinutes
		FROM #UTCMap t
		WHERE t.MapType = 0
		AND s.UTCYearBucketStart <= t.RelativeYearBucket
		AND s.UTCYearBucketEnd >= t.RelativeYearBucket
		AND s.UTCIntervalStart < t.UTCIntervalEnd
		AND s.UTCIntervalEnd > t.UTCIntervalStart
	) u
	INNER JOIN #TimeZones stz ON s.TimeZoneChecksum = stz.TimeZoneChecksum
	INNER JOIN #TimeZones ttz ON u.TargetTimeZoneChecksum = ttz.TimeZoneChecksum
	WHERE s.MapType = 1
	AND s.RelativeYearBucket NOT IN(@RequestedStartYear - 1, @RequestedEndYear + 1) -- avoid errors for out of bounds data

	UNION ALL

	-- this part returns 0 rows but tricks the optimizer into getting a better cardinality estimate to avoid various problems
	SELECT
		tz.TimeZoneChecksum,
		tz2.TimeZoneChecksum,
		DATEPART(YEAR, y.DateTruncatedToYear),
		y.DateTruncatedToYear,
		DATEADD(YEAR, 1, y.DateTruncatedToYear),
		0,
		0,
		N'',
		N''
	FROM (VALUES (1), (1), (1), (1)) n(n)
	CROSS JOIN #TimeZones tz
	CROSS JOIN #TimeZones tz2
	CROSS JOIN #AllCalendarYears y
	WHERE @Zero = 1
	OPTION (MAXDOP 1, OPTIMIZE FOR (@Zero = 1));


	DROP TABLE IF EXISTS [TimeZoneConversionHelper_RS_For_Switch];
	CREATE TABLE [dbo].[TimeZoneConversionHelper_RS_For_Switch](
		[SourceTimeZoneNameChecksum] INT NOT NULL,
		[TargetTimeZoneNameChecksum] INT NOT NULL,
		[IntervalStart] [datetime2](7) NOT NULL,
		[IntervalEnd] [datetime2](7) NOT NULL,
		[OffsetMinutes] [int] NOT NULL,
		[TargetOffsetMinutes] [int] NOT NULL,
		CONSTRAINT PK_TimeZoneConversionHelper_RS_For_Switch PRIMARY KEY ([SourceTimeZoneNameChecksum], [TargetTimeZoneNameChecksum], [IntervalStart] )
	);

	INSERT INTO [dbo].[TimeZoneConversionHelper_RS_For_Switch] WITH (TABLOCKX)
	(SourceTimeZoneNameChecksum, TargetTimeZoneNameChecksum, IntervalStart, IntervalEnd, OffsetMinutes, TargetOffsetMinutes)
	SELECT
		q2.SourceTimeZoneNameChecksum,
		TargetTimeZoneNameChecksum,
		MIN(IntervalStart),
		MAX(IntervalEnd),
		MIN(OffsetMinutes), -- ANY
		MIN(TargetOffsetMinutes)  -- ANY
	FROM
	(
		SELECT
			q.SourceTimeZoneNameChecksum,
			TargetTimeZoneNameChecksum,
			IntervalStart,
			IntervalEnd,
			OffsetMinutes,
			TargetOffsetMinutes,
			SUM(CASE WHEN IntervalStart <> PrevIntervalEnd OR OffsetMinutes <> PrevOffsetMinutes OR TargetOffsetMinutes <> PrevTargetOffsetMinutes THEN 1 ELSE 0 END) 
			OVER (PARTITION BY SourceTimeZoneNameChecksum, TargetTimeZoneNameChecksum ORDER BY IntervalStart ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) OffsetInterval
		FROM
		(
			SELECT
				SourceTimeZoneNameChecksum,
				TargetTimeZoneNameChecksum,
				IntervalStart,
				IntervalEnd,
				OffsetMinutes,
				TargetOffsetMinutes,
				LAG(IntervalEnd) OVER (PARTITION BY SourceTimeZoneNameChecksum, TargetTimeZoneNameChecksum ORDER BY IntervalStart) PrevIntervalEnd,
				LAG(OffsetMinutes) OVER (PARTITION BY SourceTimeZoneNameChecksum, TargetTimeZoneNameChecksum ORDER BY IntervalStart) PrevOffsetMinutes,
				LAG(TargetOffsetMinutes) OVER (PARTITION BY SourceTimeZoneNameChecksum, TargetTimeZoneNameChecksum ORDER BY IntervalStart) PrevTargetOffsetMinutes
			FROM TimeZoneConversionHelper_CCI_For_Switch
		) q
	) q2
	GROUP BY q2.SourceTimeZoneNameChecksum, q2.TargetTimeZoneNameChecksum, q2.OffsetInterval
	OPTION (MAXDOP 1);


	BEGIN TRANSACTION;

	TRUNCATE TABLE dbo.TimeZoneConversionHelper_CCI;
	ALTER TABLE dbo.TimeZoneConversionHelper_CCI_For_Switch SWITCH TO dbo.TimeZoneConversionHelper_CCI;

	COMMIT TRANSACTION;

	DROP TABLE IF EXISTS dbo.TimeZoneConversionHelper_CCI_For_Switch;

	-- switch does not change the statistics modified row count
	UPDATE STATISTICS TimeZoneConversionHelper_CCI;


	BEGIN TRANSACTION;

	TRUNCATE TABLE dbo.TimeZoneConversionHelper_RS;
	ALTER TABLE dbo.TimeZoneConversionHelper_RS_For_Switch SWITCH TO dbo.TimeZoneConversionHelper_RS;

	COMMIT TRANSACTION;

	DROP TABLE IF EXISTS dbo.TimeZoneConversionHelper_RS_For_Switch;

	-- switch does not change the statistics modified row count
	UPDATE STATISTICS TimeZoneConversionHelper_RS;

	RETURN;
END;
