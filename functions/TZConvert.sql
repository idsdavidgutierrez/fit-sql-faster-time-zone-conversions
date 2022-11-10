/*
Name: TZConvertDT
Purpose: Performs the equivalent of (@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName
License: MIT
Author: Joe Obbish
Full Source Code: https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions
Parameters:
	@Input - the datetime value to be converted
	@SourceTimeZoneName - the source time zone of the input in Windows standard format (see sys.time_zone_info)
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
*/
CREATE OR ALTER FUNCTION dbo.TZConvertDT (
	@Input DATETIME,
	@SourceTimeZoneName SYSNAME,
	@TargetTimeZoneName SYSNAME
)
RETURNS TABLE
AS
RETURN (
	SELECT
		output_columns.ConvertedDate,
		output_columns.ConvertedDateTime,
		output_columns.ConvertedDateTime2,
		output_columns.ConvertedDateTimeOffset
	FROM (SELECT 1) dummy (d)
	OUTER APPLY
	(
		SELECT OffsetMinutes, TargetOffsetMinutes
		FROM (
			SELECT TOP (1) OffsetMinutes, IntervalEnd, TargetOffsetMinutes
			FROM dbo.TimeZoneConversionHelper_RS l
			WHERE l.SourceTimeZoneNameChecksum = CHECKSUM(UPPER(@SourceTimeZoneName) COLLATE Latin1_General_100_BIN2)
			AND l.TargetTimeZoneNameChecksum = CHECKSUM(UPPER(@TargetTimeZoneName) COLLATE Latin1_General_100_BIN2)
			AND l.IntervalStart <= CAST(@Input AS DATETIME2(7))
			ORDER BY l.IntervalStart DESC
		) q0
		WHERE q0.IntervalEnd > CAST(@Input AS DATETIME2(7))
	) q
	CROSS APPLY (
		SELECT 
			DATEADD(MINUTE, q.OffsetMinutes, @Input) ConvertedDT,
			(@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName FallBackDTO
	) helper
	CROSS APPLY (
		SELECT
			CASE
			WHEN q.OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATE)
			ELSE CAST(helper.FallBackDTO AS DATE)
			END ConvertedDate,
			CASE
			WHEN q.OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME)
			ELSE CAST(helper.FallBackDTO AS DATETIME)
			END ConvertedDateTime,
			CASE
			WHEN q.OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME2)
			ELSE CAST(helper.FallBackDTO AS DATETIME2)
			END ConvertedDateTime2,
			CASE
			WHEN q.OffsetMinutes IS NOT NULL AND q.TargetOffsetMinutes IS NOT NULL THEN SWITCHOFFSET(DATEADD(MINUTE, q.OffsetMinutes - q.TargetOffsetMinutes, @Input), TargetOffsetMinutes)
			ELSE helper.FallBackDTO
			END ConvertedDateTimeOffset
	) output_columns
);

GO

/*
Name: TZConvertDT2
Purpose: Performs the equivalent of (@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName
License: MIT
Author: Joe Obbish
Full Source Code: https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions
Parameters:
	@Input - the datetime2 value to be converted
	@SourceTimeZoneName - the source time zone of the input in Windows standard format (see sys.time_zone_info)
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
*/
CREATE OR ALTER FUNCTION dbo.TZConvertDT2 (
	@Input DATETIME2,
	@SourceTimeZoneName SYSNAME,
	@TargetTimeZoneName SYSNAME
)
RETURNS TABLE
AS
RETURN (
	SELECT
		output_columns.ConvertedDate,
		output_columns.ConvertedDateTime,
		output_columns.ConvertedDateTime2,
		output_columns.ConvertedDateTimeOffset
	FROM (SELECT 1) dummy (d)
	OUTER APPLY
	(
		SELECT OffsetMinutes, TargetOffsetMinutes
		FROM (
			SELECT TOP (1) OffsetMinutes, IntervalEnd, TargetOffsetMinutes
			FROM dbo.TimeZoneConversionHelper_RS l
			WHERE l.SourceTimeZoneNameChecksum = CHECKSUM(UPPER(@SourceTimeZoneName) COLLATE Latin1_General_100_BIN2)
			AND l.TargetTimeZoneNameChecksum = CHECKSUM(UPPER(@TargetTimeZoneName) COLLATE Latin1_General_100_BIN2)
			AND l.IntervalStart <= @Input
			ORDER BY l.IntervalStart DESC
		) q0
		WHERE q0.IntervalEnd > @Input
	) q
	CROSS APPLY (
		SELECT 
			DATEADD(MINUTE, q.OffsetMinutes, @Input) ConvertedDT,
			(@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName FallBackDTO
	) helper
	CROSS APPLY (
		SELECT
			CASE
			WHEN q.OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATE)
			ELSE CAST(helper.FallBackDTO AS DATE)
			END ConvertedDate,
			CASE
			WHEN q.OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME)
			ELSE CAST(helper.FallBackDTO AS DATETIME)
			END ConvertedDateTime,
			CASE
			WHEN q.OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME2)
			ELSE CAST(helper.FallBackDTO AS DATETIME2)
			END ConvertedDateTime2,
			CASE
			WHEN q.OffsetMinutes IS NOT NULL AND q.TargetOffsetMinutes IS NOT NULL THEN SWITCHOFFSET(DATEADD(MINUTE, q.OffsetMinutes - q.TargetOffsetMinutes, @Input), TargetOffsetMinutes)
			ELSE helper.FallBackDTO
			END ConvertedDateTimeOffset
	) output_columns
);

GO


/*
Name: TZConvertDTO
Purpose: Performs the equivalent of @Input AT TIME ZONE @TargetTimeZoneName
License: MIT
Author: Joe Obbish
Full Source Code: https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions
Parameters:
	@Input - the datetimeoffset value to be converted
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
*/
CREATE OR ALTER FUNCTION dbo.TZConvertDTO (
	@Input DATETIMEOFFSET,
	@TargetTimeZoneName SYSNAME
)
RETURNS TABLE
AS
RETURN (
	SELECT
		output_columns.ConvertedDate,
		output_columns.ConvertedDateTime,
		output_columns.ConvertedDateTime2,
		output_columns.ConvertedDateTimeOffset
	FROM (SELECT 1) dummy (d)
	OUTER APPLY
	(
		SELECT OffsetMinutes, TargetOffsetMinutes
		FROM (
			SELECT TOP (1) OffsetMinutes, IntervalEnd, TargetOffsetMinutes
			FROM dbo.TimeZoneConversionHelper_RS l
			WHERE l.SourceTimeZoneNameChecksum = CHECKSUM(UPPER(N'UTC') COLLATE Latin1_General_100_BIN2)
			AND l.TargetTimeZoneNameChecksum = CHECKSUM(UPPER(@TargetTimeZoneName) COLLATE Latin1_General_100_BIN2)
			AND l.IntervalStart <= CAST(SWITCHOFFSET(@Input, 0) AS DATETIME2(7))
			ORDER BY l.IntervalStart DESC
		) q0
		WHERE q0.IntervalEnd > CAST(SWITCHOFFSET(@Input, 0) AS DATETIME2(7))
	) q
	CROSS APPLY (
		SELECT CASE
			WHEN q.OffsetMinutes IS NOT NULL AND q.TargetOffsetMinutes IS NOT NULL THEN
			SWITCHOFFSET(DATEADD(MINUTE, q.OffsetMinutes - q.TargetOffsetMinutes, @Input), TargetOffsetMinutes) 
			ELSE @Input AT TIME ZONE @TargetTimeZoneName END ConvertedDTO
	) helper
	CROSS APPLY (
		SELECT
			CAST(helper.ConvertedDTO AS DATE) ConvertedDate,
			CAST(helper.ConvertedDTO AS DATETIME) ConvertedDateTime,
			CAST(helper.ConvertedDTO AS DATETIME2) ConvertedDateTime2,
			helper.ConvertedDTO ConvertedDateTimeOffset
	) output_columns
);
