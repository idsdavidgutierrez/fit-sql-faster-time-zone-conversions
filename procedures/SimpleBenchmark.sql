-- turn off query result sets!

SET NOCOUNT ON;

DECLARE @PrevCPUms INT;
DECLARE @StaticTimeZoneName SYSNAME;

SELECT TOP (1) @StaticTimeZoneName = SourceTimeZoneName
FROM TimeZoneConversionHelper_CCI
WHERE SourceTimeZoneName <> N'UTC';


DROP TABLE IF EXISTS #SourceData;
CREATE TABLE #SourceData (
	SourceDateTime DATETIME NOT NULL,
	SourceTimeZoneName SYSNAME NOT NULL,
	TargetTimeZoneName SYSNAME NOT NULL
);

DROP TABLE IF EXISTS #res;
CREATE TABLE #res (
	TestType VARCHAR(100) NOT NULL,
	UTCToStaticCPUms INT NULL,
	UTCToDynamicCPUms INT NULL,
	StaticToDynamicCPUms INT NULL,
	DynamicToDynamicCPUms INT NULL
);

INSERT INTO #res (TestType)
VALUES ('AT TIME ZONE'), ('SIMPLE'), ('PAIR');

DROP TABLE IF EXISTS #all_tz;
CREATE TABLE #all_tz (
	TimeZoneName SYSNAME NOT NULL
);

INSERT INTO #all_tz (TimeZoneName)
SELECT [name]
FROM sys.time_zone_info;


INSERT INTO #SourceData (SourceDateTime, SourceTimeZoneName, TargetTimeZoneName)
SELECT TOP (1000000)
DATEADD(SECOND, 31.53 * ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), '20210101'),
t1.TimeZoneName,
t2.TimeZoneName
FROM #all_tz t1
CROSS JOIN #all_tz t2
CROSS JOIN #all_tz t3;

-- UTCToStaticCPUms

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT SWITCHOFFSET(SourceDateTime, 0) AT TIME ZONE @StaticTimeZoneName
FROM #SourceData
OPTION (MAXDOP 1);
UPDATE #res SET UTCToStaticCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'AT TIME ZONE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT c1.ConvertedDateTimeOffset
FROM #SourceData
CROSS APPLY dbo.TZConvertDT(SourceDateTime, N'UTC', @StaticTimeZoneName) c1
OPTION (MAXDOP 1);
UPDATE #res SET UTCToStaticCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'SIMPLE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT f1.ConvertedDateTimeOffset
FROM #SourceData
OUTER APPLY dbo.TZGetOffsetsDT(SourceDateTime, N'UTC', @StaticTimeZoneName) o1
CROSS APPLY dbo.TZFormatDT(SourceDateTime, N'UTC', @StaticTimeZoneName, o1.OffsetMinutes, o1.TargetOffsetMinutes) f1
OPTION (MAXDOP 1);
UPDATE #res SET UTCToStaticCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'PAIR';


-- UTCToDynamicCPUms

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT SWITCHOFFSET(SourceDateTime, 0) AT TIME ZONE TargetTimeZoneName
FROM #SourceData
OPTION (MAXDOP 1);
UPDATE #res SET UTCToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'AT TIME ZONE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT c1.ConvertedDateTimeOffset
FROM #SourceData
CROSS APPLY dbo.TZConvertDT(SourceDateTime, N'UTC', TargetTimeZoneName) c1
OPTION (MAXDOP 1);
UPDATE #res SET UTCToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'SIMPLE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT f1.ConvertedDateTimeOffset
FROM #SourceData
OUTER APPLY dbo.TZGetOffsetsDT(SourceDateTime, N'UTC', TargetTimeZoneName) o1
CROSS APPLY dbo.TZFormatDT(SourceDateTime, N'UTC', @StaticTimeZoneName, o1.OffsetMinutes, o1.TargetOffsetMinutes) f1
OPTION (MAXDOP 1);
UPDATE #res SET UTCToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'PAIR';


-- StaticToDynamicCPUms

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT SourceDateTime AT TIME ZONE @StaticTimeZoneName AT TIME ZONE TargetTimeZoneName
FROM #SourceData
OPTION (MAXDOP 1);
UPDATE #res SET StaticToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'AT TIME ZONE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT c1.ConvertedDateTimeOffset
FROM #SourceData
CROSS APPLY dbo.TZConvertDT(SourceDateTime, @StaticTimeZoneName, TargetTimeZoneName) c1
OPTION (MAXDOP 1);
UPDATE #res SET StaticToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'SIMPLE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT f1.ConvertedDateTimeOffset
FROM #SourceData
OUTER APPLY dbo.TZGetOffsetsDT(SourceDateTime, @StaticTimeZoneName, TargetTimeZoneName) o1
CROSS APPLY dbo.TZFormatDT(SourceDateTime, @StaticTimeZoneName, @StaticTimeZoneName, o1.OffsetMinutes, o1.TargetOffsetMinutes) f1
OPTION (MAXDOP 1);
UPDATE #res SET StaticToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'PAIR';


-- DynamicToDynamicCPUms

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT SourceDateTime AT TIME ZONE SourceTimeZoneName AT TIME ZONE TargetTimeZoneName
FROM #SourceData
OPTION (MAXDOP 1);
UPDATE #res SET DynamicToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'AT TIME ZONE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT c1.ConvertedDateTimeOffset
FROM #SourceData
CROSS APPLY dbo.TZConvertDT(SourceDateTime, SourceTimeZoneName, TargetTimeZoneName) c1
OPTION (MAXDOP 1);
UPDATE #res SET DynamicToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'SIMPLE';

SELECT @PrevCPUms = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
SELECT f1.ConvertedDateTimeOffset
FROM #SourceData
OUTER APPLY dbo.TZGetOffsetsDT(SourceDateTime, SourceTimeZoneName, TargetTimeZoneName) o1
CROSS APPLY dbo.TZFormatDT(SourceDateTime, SourceTimeZoneName, @StaticTimeZoneName, o1.OffsetMinutes, o1.TargetOffsetMinutes) f1
OPTION (MAXDOP 1);
UPDATE #res SET DynamicToDynamicCPUms = (SELECT cpu_time - @PrevCPUms FROM sys.dm_exec_requests WHERE session_id = @@SPID)
WHERE TestType = 'PAIR';

GO

-- turn on result sets
SELECT * FROM #res;
