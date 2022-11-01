/*
Name: TZFormatDT
Purpose: performs the equivalent of (@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName
Parameters:
	@Input - the datetime value to be converted
	@SourceTimeZoneName - the source time zone of the input in Windows standard format (see sys.time_zone_info)
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
	@OffsetMinutes - the OffsetMinutes value returned from dbo.TZGetOffsetsDT()
	@TargetOffsetMinutes - the TargetOffsetMinutes value returned from dbo.TZGetOffsetsDT()
*/
CREATE OR ALTER FUNCTION dbo.TZFormatDT (
	@Input DATETIME,
	@SourceTimeZoneName SYSNAME,
	@TargetTimeZoneName SYSNAME,
	@OffsetMinutes INT,
	@TargetOffsetMinutes INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
	SELECT
		output_columns.ConvertedDate,
		output_columns.ConvertedDateTime,
		output_columns.ConvertedDateTime2,
		output_columns.ConvertedDateTimeOffset
	FROM
	(
		SELECT 
			DATEADD(MINUTE, @OffsetMinutes, @Input) ConvertedDT,
			(@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName FallBackDTO
	) helper
	CROSS APPLY (
		SELECT
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATE)
			ELSE CAST(helper.FallBackDTO AS DATE)
			END ConvertedDate,
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME)
			ELSE CAST(helper.FallBackDTO AS DATETIME)
			END ConvertedDateTime,
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME2)
			ELSE CAST(helper.FallBackDTO AS DATETIME2)
			END ConvertedDateTime2,
			CASE
			WHEN @OffsetMinutes IS NOT NULL AND @TargetOffsetMinutes IS NOT NULL THEN SWITCHOFFSET(DATEADD(MINUTE, @OffsetMinutes - @TargetOffsetMinutes, @Input), @TargetOffsetMinutes)
			ELSE helper.FallBackDTO
			END ConvertedDateTimeOffset
	) output_columns
);

GO



/*
Name: TZFormatDT2
Purpose: performs the equivalent of (@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName
Parameters:
	@Input - the datetime value to be converted
	@SourceTimeZoneName - the source time zone of the input in Windows standard format (see sys.time_zone_info)
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
	@OffsetMinutes - the OffsetMinutes value returned from dbo.TZGetOffsetsDT2()
	@TargetOffsetMinutes - the TargetOffsetMinutes value returned from dbo.TZGetOffsetsDT2()
*/
CREATE OR ALTER FUNCTION dbo.TZFormatDT2 (
	@Input DATETIME2,
	@SourceTimeZoneName SYSNAME,
	@TargetTimeZoneName SYSNAME,
	@OffsetMinutes INT,
	@TargetOffsetMinutes INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
	SELECT
		output_columns.ConvertedDate,
		output_columns.ConvertedDateTime,
		output_columns.ConvertedDateTime2,
		output_columns.ConvertedDateTimeOffset
	FROM
	(
		SELECT 
			DATEADD(MINUTE, @OffsetMinutes, @Input) ConvertedDT,
			(@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName FallBackDTO
	) helper
	CROSS APPLY (
		SELECT
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATE)
			ELSE CAST(helper.FallBackDTO AS DATE)
			END ConvertedDate,
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME)
			ELSE CAST(helper.FallBackDTO AS DATETIME)
			END ConvertedDateTime,
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME2)
			ELSE CAST(helper.FallBackDTO AS DATETIME2)
			END ConvertedDateTime2,
			CASE
			WHEN @OffsetMinutes IS NOT NULL AND @TargetOffsetMinutes IS NOT NULL THEN SWITCHOFFSET(DATEADD(MINUTE, @OffsetMinutes - @TargetOffsetMinutes, @Input), @TargetOffsetMinutes)
			ELSE helper.FallBackDTO
			END ConvertedDateTimeOffset
	) output_columns
);

GO


/*
Name: TZFormatDTO
Purpose: performs the equivalent of @Input AT TIME ZONE @TargetTimeZoneName
Parameters:
	@Input - the datetime value to be converted
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
	@OffsetMinutes - the OffsetMinutes value returned from dbo.TZGetOffsetsDTO()
	@TargetOffsetMinutes - the TargetOffsetMinutes value returned from dbo.TZGetOffsetsDTO()
*/
CREATE OR ALTER FUNCTION dbo.TZFormatDTO (
	@Input DATETIMEOFFSET,
	@TargetTimeZoneName SYSNAME,
	@OffsetMinutes INT,
	@TargetOffsetMinutes INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
	SELECT
		output_columns.ConvertedDate,
		output_columns.ConvertedDateTime,
		output_columns.ConvertedDateTime2,
		output_columns.ConvertedDateTimeOffset
	FROM
	(
		SELECT 
			DATEADD(MINUTE, @OffsetMinutes, @Input) ConvertedDT,
			@Input AT TIME ZONE @TargetTimeZoneName FallBackDTO
	) helper
	CROSS APPLY (
		SELECT
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATE)
			ELSE CAST(helper.FallBackDTO AS DATE)
			END ConvertedDate,
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME)
			ELSE CAST(helper.FallBackDTO AS DATETIME)
			END ConvertedDateTime,
			CASE
			WHEN @OffsetMinutes IS NOT NULL THEN CAST(helper.ConvertedDT AS DATETIME2)
			ELSE CAST(helper.FallBackDTO AS DATETIME2)
			END ConvertedDateTime2,
			CASE
			WHEN @OffsetMinutes IS NOT NULL AND @TargetOffsetMinutes IS NOT NULL THEN SWITCHOFFSET(DATEADD(MINUTE, @OffsetMinutes - @TargetOffsetMinutes, @Input), @TargetOffsetMinutes)
			ELSE helper.FallBackDTO
			END ConvertedDateTimeOffset
	) output_columns
);
