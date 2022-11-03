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
		SET @PaddedEndDate = DATEADD(HOUR, 24, CAST(DATEFROMPARTS(@RequestedEndYear, 12, 31) AS DATETIME2));
		SET @SamplePointsNeeded = CEILING(1.0 * DATEDIFF(HOUR, @PaddedStartDate, @PaddedEndDate) / @SampleHours);
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH;

	-- use @TimeZoneFilter if it has at least one row, otherwise get all time zones
	CREATE TABLE #TimeZones (TimeZoneName SYSNAME NOT NULL, PRIMARY KEY (TimeZoneName)); 

	IF EXISTS (SELECT 1 FROM @TimeZoneFilter)
	BEGIN
		INSERT INTO #TimeZones (TimeZoneName)
		SELECT TimeZoneName
		FROM @TimeZoneFilter

		UNION

		SELECT N'UTC';
	END
	ELSE
	BEGIN
		INSERT INTO #TimeZones (TimeZoneName)
		SELECT [name]
		FROM sys.time_zone_info;
	END;


	CREATE TABLE #AddForBatchMode (I INT);
	IF ISNULL(SERVERPROPERTY('IsTempDBMetadataMemoryOptimized'), 0) = 0
	BEGIN
		CREATE CLUSTERED COLUMNSTORE INDEX CCI ON #AddForBatchMode;
	END;

	-- Used later for partition switching so must match TimeZoneConversionHelper exactly
	DROP TABLE IF EXISTS dbo.TimeZoneConversionHelper_TEMP;
	CREATE TABLE dbo.TimeZoneConversionHelper_TEMP (
		SourceTimeZoneName SYSNAME NOT NULL,
		TargetTimeZoneName SYSNAME NOT NULL,
		YearBucket SMALLINT NOT NULL,
		IntervalStart DATETIME2(0) NOT NULL,
		IntervalEnd DATETIME2(0) NOT NULL,
		OffsetMinutes INT NOT NULL, -- DATEADD uses an INT parameter
		TargetOffsetMinutes INT NOT NULL,
		INDEX CI_TimeZoneConversionHelper_TEMP CLUSTERED (SourceTimeZoneName, TargetTimeZoneName, YearBucket, IntervalStart) 
	);

	CREATE TABLE #AllSamplePoints (
		SamplePoint DATETIME2(0) NOT NULL,
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
		DateTruncatedToYear DATETIME2(0) NOT NULL,
		PRIMARY KEY (DateTruncatedToYear)
	);

	INSERT INTO #AllCalendarYears (DateTruncatedToYear)
	SELECT DISTINCT DATEFROMPARTS(DATEPART(YEAR, SamplePoint), 1, 1)   
	FROM #AllSamplePoints

	UNION 

	SELECT DATEFROMPARTS(@RequestedEndYear + 1, 1, 1)

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
		TimeZoneName SYSNAME NOT NULL,
		SamplePoint DATETIME2(0) NOT NULL,
		OffsetMinutes INT NOT NULL,
		PRIMARY KEY (MapType, TimeZoneName, SamplePoint)
	);

	-- must sample map type 0 first due to AT TIME ZONE bug
	INSERT INTO #SampledTimeZoneOffsets (MapType, TimeZoneName, SamplePoint, OffsetMinutes)
	SELECT
		0,
		tz.TimeZoneName,
		cd.SamplePoint,
		o.OffsetMinutes
	FROM #TimeZones tz
	CROSS JOIN #AllSamplePoints cd
	CROSS APPLY (
		SELECT DATEDIFF(MINUTE, cd.SamplePoint, CAST(SWITCHOFFSET(cd.SamplePoint, 0) AT TIME ZONE tz.TimeZoneName AS DATETIME2(0)))
	) o (OffsetMinutes)
	LEFT OUTER JOIN #AddForBatchMode z ON 1 = 0
	WHERE tz.TimeZoneName <> N'UTC'
	OPTION (MAXDOP 1, NO_PERFORMANCE_SPOOL);


	CREATE TABLE #TimeZonesWithConstantOffsetToUTC (
		TimeZoneName SYSNAME NOT NULL,
		OffsetMinutesFromUTC INT NOT NULL,
		PRIMARY KEY (TimeZoneName)
	);
	
	INSERT INTO #TimeZonesWithConstantOffsetToUTC (TimeZoneName, OffsetMinutesFromUTC)
	SELECT TimeZoneName, MIN(OffsetMinutes)
	FROM #SampledTimeZoneOffsets
	GROUP BY TimeZoneName
	HAVING MIN(OffsetMinutes) = MAX(OffsetMinutes)

	UNION ALL

	SELECT N'UTC', 0
	OPTION (MAXDOP 1);


	INSERT INTO #SampledTimeZoneOffsets (MapType, TimeZoneName, SamplePoint, OffsetMinutes)
	SELECT
		1,
		tz.TimeZoneName,
		cd.SamplePoint,
		o.OffsetMinutes
	FROM #TimeZones tz
	CROSS JOIN #AllSamplePoints cd
	CROSS APPLY (
		SELECT DATEDIFF(MINUTE, cd.SamplePoint, CAST(SWITCHOFFSET(cd.SamplePoint AT TIME ZONE tz.TimeZoneName, 0) AS DATETIME2(0)))
	) o (OffsetMinutes)
	LEFT OUTER JOIN #AddForBatchMode z ON 1 = 0
	WHERE NOT EXISTS (
		SELECT 1
		FROM #TimeZonesWithConstantOffsetToUTC t
		WHERE tz.TimeZoneName = t.TimeZoneName
	)
	OPTION (MAXDOP 1, NO_PERFORMANCE_SPOOL);


	CREATE TABLE #IntervalGroups (
		MapType TINYINT NOT NULL,
		TimeZoneName SYSNAME NOT NULL,
		PreviousIntervalEnd DATETIME2(0) NOT NULL,
		IntervalStart DATETIME2(0) NOT NULL,
		PreviousOffsetMinutes INT NOT NULL,
		OffsetMinutes INT NOT NULL
	);

	INSERT INTO #IntervalGroups (MapType, TimeZoneName, PreviousIntervalEnd, IntervalStart, PreviousOffsetMinutes, OffsetMinutes)
	SELECT
		MapType,
		TimeZoneName,
		PreviousSamplePoint,
		SamplePoint,
		PreviousOffsetMinutes,
		OffsetMinutes
	FROM
	(
		SELECT
			MapType,
			TimeZoneName,
			cd.SamplePoint,
			cd.OffsetMinutes,
			LAG(SamplePoint) OVER (PARTITION BY MapType, TimeZoneName ORDER BY SamplePoint) PreviousSamplePoint,
			LAG(cd.OffsetMinutes) OVER (PARTITION BY MapType, TimeZoneName ORDER BY cd.SamplePoint) PreviousOffsetMinutes
			FROM #SampledTimeZoneOffsets cd
			LEFT OUTER JOIN #AddForBatchMode z ON 1 = 0
			WHERE NOT EXISTS (
				SELECT 1
				FROM #TimeZonesWithConstantOffsetToUTC t
				WHERE cd.TimeZoneName = t.TimeZoneName
			)
		) q
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
				 AS DATETIME2(0))
			) MidOffsetMinutes
		) ca2
		WHERE DATEDIFF(MINUTE, PreviousIntervalEnd, IntervalStart) > 1
		OPTION (MAXDOP 1);

		SET @MergeIntervalCount += 1;
	END;

	CREATE TABLE #UTCMapNoBucket (
		MapType TINYINT NOT NULL,
		TimeZoneName SYSNAME NOT NULL,		
		IntervalStart DATETIME2(0) NOT NULL,
		IntervalEnd DATETIME2(0) NOT NULL,
		OffsetMinutes INT NOT NULL,
		PRIMARY KEY (MapType, TimeZoneName, IntervalStart)
	);


	INSERT INTO #UTCMapNoBucket (MapType, TimeZoneName, IntervalStart, IntervalEnd, OffsetMinutes)
	SELECT src.MapType, src.TimeZoneName, src.IntervalStart, src.IntervalEnd, src.OffsetMinutes
	FROM (
		SELECT
			MapType,
			TimeZoneName,
			IntervalStart,
			ISNULL(LEAD(PreviousIntervalEnd) OVER (PARTITION BY MapType, TimeZoneName ORDER BY IntervalStart), @PaddedEndDate) IntervalEnd,		
			OffsetMinutes
		FROM #IntervalGroups
		LEFT OUTER JOIN #AddForBatchMode z ON 1 = 0

		UNION ALL

		SELECT MapType, TimeZoneName, @PaddedStartDate, PreviousIntervalEnd, PreviousOffsetMinutes
		FROM (
			SELECT MapType, TimeZoneName, PreviousIntervalEnd, PreviousOffsetMinutes,
			ROW_NUMBER() OVER (PARTITION BY MapType, TimeZoneName ORDER BY IntervalStart) RN
			FROM #IntervalGroups
		) q
		WHERE q.RN = 1
	) src
	OPTION (MAXDOP 1);


	CREATE TABLE #UTCMap (
		MapType TINYINT NOT NULL,
		RelativeYearBucket SMALLINT NOT NULL, -- can be local or UTC
		TimeZoneName SYSNAME NOT NULL,	
		UTCIntervalStart DATETIME2(0) NOT NULL,
		UTCIntervalEnd DATETIME2(0) NOT NULL,
		-- these four are only set for target -> UTC
		LocalIntervalStart DATETIME2(0) NULL,
		LocalIntervalEnd DATETIME2(0) NULL,
		UTCYearBucketStart SMALLINT NULL,
		UTCYearBucketEnd SMALLINT NULL,		
		OffsetMinutes INT NOT NULL, -- always set
		INDEX CI CLUSTERED (MapType, RelativeYearBucket)
	);

	INSERT INTO #UTCMap (MapType, TimeZoneName, RelativeYearBucket, UTCIntervalStart, UTCIntervalEnd, 
	LocalIntervalStart, LocalIntervalEnd, UTCYearBucketStart, UTCYearBucketEnd,	OffsetMinutes)
	SELECT 
		MapType,
		TimeZoneName,
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
			TimeZoneName,
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
			tz.TimeZoneName,
			DATEPART(YEAR, y.DateTruncatedToYear),
			y.DateTruncatedToYear,
			DATEADD(YEAR, 1, y.DateTruncatedToYear),
			-1 * tz.OffsetMinutesFromUTC -- reverse for target -> UTC
		FROM #TimeZonesWithConstantOffsetToUTC tz
		CROSS JOIN #AllCalendarYears y
	) q
	OUTER APPLY (
		SELECT		
			DATEPART(YEAR, CAST(SWITCHOFFSET(IntervalStart AT TIME ZONE TimeZoneName, 0) AS DATETIME2(0))) UTCYearBucketStart,
			DATEPART(YEAR, CAST(SWITCHOFFSET(IntervalEnd AT TIME ZONE TimeZoneName, 0) AS DATETIME2(0))) UTCYearBucketEnd,
			SWITCHOFFSET(IntervalStart AT TIME ZONE TimeZoneName, 0) UTCIntervalStart,
			SWITCHOFFSET(IntervalEnd AT TIME ZONE TimeZoneName, 0) UTCIntervalEnd
		WHERE MapType = 1
	) ca

	UNION ALL

	SELECT
		0,
		tz.TimeZoneName,
		DATEPART(YEAR, y.DateTruncatedToYear),
		y.DateTruncatedToYear,
		DATEADD(YEAR, 1, y.DateTruncatedToYear),
		NULL,
		NULL,
		NULL,
		NULL,
		tz.OffsetMinutesFromUTC
	FROM #TimeZonesWithConstantOffsetToUTC tz
	CROSS JOIN #AllCalendarYears y
	OPTION (MAXDOP 1);
	 	

	DECLARE @Zero INT = 0;

	INSERT INTO TimeZoneConversionHelper_TEMP (SourceTimeZoneName, TargetTimeZoneName, YearBucket, IntervalStart, IntervalEnd, OffsetMinutes, TargetOffsetMinutes)
	SELECT
		s.TimeZoneName,
		u.TargetTimeZoneName, 
		s.RelativeYearBucket,
		CASE WHEN u.UTCIntervalStart > s.UTCIntervalStart THEN DATEADD(MINUTE, DATEDIFF(MINUTE, s.UTCIntervalStart, u.UTCIntervalStart), s.LocalIntervalStart)
		ELSE s.LocalIntervalStart END IntervalStart,
		CASE WHEN u.UTCIntervalEnd < s.UTCIntervalEnd THEN DATEADD(MINUTE, DATEDIFF(MINUTE, s.UTCIntervalStart, u.UTCIntervalEnd), s.LocalIntervalStart)
		ELSE s.LocalIntervalEnd END IntervalStart,
		s.OffsetMinutes + u.OffsetMinutes OffsetMinutes,
		u.OffsetMinutes
	FROM #UTCMap s
	CROSS APPLY (
		SELECT
			t.TimeZoneName AS TargetTimeZoneName,
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
	WHERE s.MapType = 1
	AND s.RelativeYearBucket NOT IN(@RequestedStartYear - 1, @RequestedEndYear + 1) -- avoid errors for out of bounds data

	UNION ALL

	-- this part returns 0 rows but tricks the optimizer into getting a better cardinality estimate to hopefully avoid a spilled sort
	SELECT
		tz.TimeZoneName,
		tz2.TimeZoneName,
		DATEPART(YEAR, y.DateTruncatedToYear),
		y.DateTruncatedToYear,
		DATEADD(YEAR, 1, y.DateTruncatedToYear),
		0,
		0
	FROM (VALUES (1), (1), (1), (1)) n(n)
	CROSS JOIN #TimeZones tz
	CROSS JOIN #TimeZones tz2
	CROSS JOIN #AllCalendarYears y
	WHERE @Zero = 1
	OPTION (MAXDOP 1, OPTIMIZE FOR (@Zero = 1));

	BEGIN TRANSACTION;

	TRUNCATE TABLE dbo.TimeZoneConversionHelper;

	ALTER TABLE dbo.TimeZoneConversionHelper_TEMP SWITCH TO dbo.TimeZoneConversionHelper;

	COMMIT TRANSACTION;

	DROP TABLE IF EXISTS dbo.TimeZoneConversionHelper_TEMP;

	-- switch does not change the statistics modified row count
	UPDATE STATISTICS TimeZoneConversionHelper;

	RETURN;
END;
