CREATE TABLE dbo.TimeZoneConversionHelper (
	SourceTimeZoneName SYSNAME NOT NULL,
	TargetTimeZoneName SYSNAME NOT NULL,
	YearBucket SMALLINT NOT NULL,
	IntervalStart DATETIME2(0) NOT NULL,
	IntervalEnd DATETIME2(0) NOT NULL,
	OffsetMinutes INT NOT NULL,
	TargetOffsetMinutes INT NOT NULL,
	INDEX CI_TimeZoneConversionHelper CLUSTERED (SourceTimeZoneName, TargetTimeZoneName, YearBucket, IntervalStart) 
);
