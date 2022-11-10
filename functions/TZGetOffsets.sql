/*
Name: TZGetOffsetsDT
Purpose: Returns a pair of offset values to be used as parameters for dbo.TZFormatDT
License: MIT
Author: Joe Obbish
Full Source Code: https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions
Parameters:
	@Input - the datetime value to be converted
	@SourceTimeZoneName - the source time zone of the input in Windows standard format (see sys.time_zone_info)
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
WARNING: call this function with OUTER APPLY instead of CROSS APPLY
*/
CREATE OR ALTER FUNCTION dbo.TZGetOffsetsDT (
	@Input DATETIME,
	@SourceTimeZoneName SYSNAME,
	@TargetTimeZoneName SYSNAME
)
RETURNS TABLE
AS
RETURN (
	SELECT OffsetMinutes, TargetOffsetMinutes
	FROM dbo.TimeZoneConversionHelper_CCI l
	WHERE l.SourceTimeZoneNameChecksum = CHECKSUM(UPPER(@SourceTimeZoneName) COLLATE Latin1_General_100_BIN2)
	AND l.TargetTimeZoneNameChecksum = CHECKSUM(UPPER(@TargetTimeZoneName) COLLATE Latin1_General_100_BIN2)
	--AND l.SourceTimeZoneName = @SourceTimeZoneName
	--AND l.TargetTimeZoneName = @TargetTimeZoneName
	AND l.YearBucket = DATEPART(YEAR, @Input)
	AND l.IntervalStart <= CAST(@Input AS DATETIME2(7))
	AND l.IntervalEnd > CAST(@Input AS DATETIME2(7))
);

GO

/*
Name: TZGetOffsetsDT2
Purpose: Returns a pair of offset values to be used as parameters for dbo.TZFormatDT2
License: MIT
Author: Joe Obbish
Full Source Code: https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions
Parameters:
	@Input - the datetime2 value to be converted
	@SourceTimeZoneName - the source time zone of the input in Windows standard format (see sys.time_zone_info)
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
WARNING: call this function with OUTER APPLY instead of CROSS APPLY
*/
CREATE OR ALTER FUNCTION dbo.TZGetOffsetsDT2 (
	@Input DATETIME2,
	@SourceTimeZoneName SYSNAME,
	@TargetTimeZoneName SYSNAME
)
RETURNS TABLE
AS
RETURN (
	SELECT OffsetMinutes, TargetOffsetMinutes
	FROM dbo.TimeZoneConversionHelper_CCI l
	WHERE l.SourceTimeZoneNameChecksum = CHECKSUM(UPPER(@SourceTimeZoneName) COLLATE Latin1_General_100_BIN2)
	AND l.TargetTimeZoneNameChecksum = CHECKSUM(UPPER(@TargetTimeZoneName) COLLATE Latin1_General_100_BIN2)
	--AND l.SourceTimeZoneName = @SourceTimeZoneName
	--AND l.TargetTimeZoneName = @TargetTimeZoneName
	AND l.YearBucket = DATEPART(YEAR, @Input)
	AND l.IntervalStart <= @Input
	AND l.IntervalEnd > @Input
);

GO


/*
Name: TZGetOffsetsDTO
Purpose: Returns a pair of offset values to be used as parameters for dbo.TZFormatDTO
License: MIT
Author: Joe Obbish
Full Source Code: https://github.com/idsdavidgutierrez/fit-sql-faster-time-zone-conversions
Parameters:
	@Input - the datetime2 value to be converted
	@TargetTimeZoneName - the target time zone of the input in Windows standard format (see sys.time_zone_info)
WARNING: call this function with OUTER APPLY instead of CROSS APPLY
*/
CREATE OR ALTER FUNCTION dbo.TZGetOffsetsDTO (
	@Input DATETIMEOFFSET,
	@TargetTimeZoneName SYSNAME
)
RETURNS TABLE
AS
RETURN (
	SELECT OffsetMinutes, TargetOffsetMinutes
	FROM dbo.TimeZoneConversionHelper_CCI l
	WHERE l.SourceTimeZoneNameChecksum = CHECKSUM(UPPER(N'UTC') COLLATE Latin1_General_100_BIN2)
	AND l.TargetTimeZoneNameChecksum = CHECKSUM(UPPER(@TargetTimeZoneName) COLLATE Latin1_General_100_BIN2)
	-- AND l.SourceTimeZoneName = N'UTC'
	-- AND l.TargetTimeZoneName = @TargetTimeZoneName
	AND l.YearBucket = DATEPART(YEAR, SWITCHOFFSET(@Input, 0))
	AND l.IntervalStart <= CAST(SWITCHOFFSET(@Input, 0) AS DATETIME2(7))
	AND l.IntervalEnd > CAST(SWITCHOFFSET(@Input, 0) AS DATETIME2(7))
);
