# Introduction

Microsoft introduced the [`AT TIME ZONE`](https://learn.microsoft.com/en-us/sql/t-sql/queries/at-time-zone-transact-sql?view=sql-server-ver16) operator with the SQL Server 2016 release. That operator may be a performance bottleneck for queries which need to perform many time zone calculations. This repository contains table-valued functions that serve as a replacement for `AT TIME ZONE`. The replacement functions perform 3-20X better than `AT TIME ZONE` under typical conditions.

# Simple Benchmark Results

A simple benchmark test was done that compares different calculation methods over a table of one million rows. The measurements are in CPU milliseconds for four different cases and three different test methods. Results for SQL Server 2019 Developer Edition:

![image](https://user-images.githubusercontent.com/33984311/200423273-90d85703-ac97-4531-b8b1-82c70f5e1dc6.png)

Microsoft made performance improvements to `AT TIME ZONE` in Azure SQL Database at some point. I suspect that similar improvements are also available in SQL Server 2022 based on RC1 test results. Results for Azure SQL Database:

![image](https://user-images.githubusercontent.com/33984311/200423936-c1c01dfb-77af-476f-9c90-eaef338a281a.png)


# Requirements

The code works on SQL Server 2016 SP1 and later, SQL Server 2017 and later, and Azure SQL Database. It likely works on Azure SQL Managed Instance as well but this has not been tested.

The `RefreshTimeZoneConversionHelperTable` stored procedure must be scheduled to execute on a recurring basis.

# Functions

Two different methods of calculating time zone changes are provided. The first method uses a pair of functions that allows for both hash and nested loop joins against the `TimeZoneConversionHelper` table. This method will generally perform better than the simple functions, especially against columnstore tables or when processing lots of data. The first function in the pair returns offset values which are fed as input parameters into the second function that provides the formatted value in the requested time zone.

The simple functions perform the calculation with only one function call but they are limited to nested loop joins only. Think of a nested loop join as an algorithm that requires a small, fixed calculation cost per row for each `AT TIME ZONE` calculation that is replaced.

## Function Pairs (performs better but harder to call)

See the Examples section for an example of how the two function types documented below work together. 

Functions `TZGetOffsetsDT`, `TZGetOffsetsDT2`, and `TZGetOffsetsDTO` are provided to return offset values which are needed for the format functions. These functions must be called with `OUTER APPLY` because they may return an empty set. Each function takes a different type of input data type. 

Arguments for `TZGetOffsetsDT`:
- @Input - DATETIME - the datetime value to be converted
- @SourceTimeZoneName - SYSNAME - the source time zone of the input in Windows standard format (see sys.time_zone_info)
- @TargetTimeZoneName - SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)

Arguments for `TZGetOffsetsDT2`:
- @Input - DATETIME2 - the datetime2 value to be converted
- @SourceTimeZoneName - SYSNAME - the source time zone of the input in Windows standard format (see sys.time_zone_info)
- @TargetTimeZoneName - SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)

Arguments for `TZGetOffsetsDTO`:
- @Input - DATETIMEOFFSET - the datetimeoffset value to be converted
- @TargetTimeZoneName - SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)

All three functions have the same two column result set:
- OffsetMinutes - INT - An interval value used as an input to the corresponding TZFormat function
- TargetOffsetMinutes - INT - An interval value used as an input to the corresponding TZFormat function

Functions `TZFormatDT`, `TZFormatDT2`, and `TZFormatDTO` are provided to perform the equivalent of `(@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName`. They must be paired with the corresponding TZGetOffsets function. These functions can be called with `OUTER APPLY` or `CROSS APPLY`. Each function takes a different type of input data type. 

Arguments for `TZFormatDT`:
- @Input - DATEIME - the datetime value to be converted
- @SourceTimeZoneName - SYSNAME - the source time zone of the input in Windows standard format (see sys.time_zone_info)
- @TargetTimeZoneName- SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)
- @OffsetMinutes - INT - the OffsetMinutes value returned from dbo.TZGetOffsetsDT()
- @TargetOffsetMinutes - INT- the TargetOffsetMinutes value returned from dbo.TZGetOffsetsDT()

Arguments for `TZFormatDT2`:
- @Input - DATEIME2 - the datetime2 value to be converted
- @SourceTimeZoneName - SYSNAME - the source time zone of the input in Windows standard format (see sys.time_zone_info)
- @TargetTimeZoneName- SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)
- @OffsetMinutes - INT - the OffsetMinutes value returned from dbo.TZGetOffsetsDT2()
- @TargetOffsetMinutes - INT- the TargetOffsetMinutes value returned from dbo.TZGetOffsetsDT2()

Arguments for `TZFormatDTO`:
- @Input - DATEIMEOFFSET - the datetimeoffset value to be converted
- @TargetTimeZoneName- SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)
- @OffsetMinutes - INT - the OffsetMinutes value returned from dbo.TZGetOffsetsDTO()
- @TargetOffsetMinutes - INT- the TargetOffsetMinutes value returned from dbo.TZGetOffsetsDTO()

All three functions have the same four column result set:
- ConvertedDate - the converted value as a DATE data type
- ConvertedDateTime - the converted value as a DATETIME data type
- ConvertedDateTime2 - the converted value as a DATETIME2 data type
- ConvertedDateTimeOffset - the converted value as a DATETIMEOFFSET data type


## Simple Functions (performs worse but easier to call)

Functions `TZConvertDT`, `TZConvertDT2`, and `TZConvertDTO` are provided to perform the equivalent of `(@Input AT TIME ZONE @SourceTimeZoneName) AT TIME ZONE @TargetTimeZoneName`. Each function takes a different type of input data type. These functions can be called with `OUTER APPLY` or `CROSS APPLY`.

Arguments for `TZConvertDT`:
 - @Input - DATETIME - the datetime value to be converted
 - @SourceTimeZoneName - SYSNAME - the source time zone of the input in Windows standard format (see sys.time_zone_info)
 - @TargetTimeZoneName - SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)

Arguments for `TZConvertDT2`:
 - @Input - DATETIME2 - the datetime2 value to be converted
 - @SourceTimeZoneName - SYSNAME - the source time zone of the input in Windows standard format (see sys.time_zone_info)
 - @TargetTimeZoneName - SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)
 
Arguments for `TZConvertDT2`:
 - @Input - DATETIMEOFFSET - the datetimeoffset value to be converted
 - @TargetTimeZoneName - SYSNAME - the target time zone of the input in Windows standard format (see sys.time_zone_info)

All three functions have the same four column result set:
- ConvertedDate - the converted value as a DATE data type
- ConvertedDateTime - the converted value as a DATETIME data type
- ConvertedDateTime2 - the converted value as a DATETIME2 data type
- ConvertedDateTimeOffset - the converted value as a DATETIMEOFFSET data type


# Examples

```TSQL
DECLARE @t TABLE (
	InputDateTime DATETIME,
	InputDateTime2 DATETIME2(7),
	InputDateTimeOffset DATETIMEOFFSET,
	SourceTimeZone SYSNAME,
	TargetTimeZone SYSNAME
);

INSERT INTO @t (InputDateTime, InputDateTime2, InputDateTimeOffset, SourceTimeZone, TargetTimeZone)
VALUES (GETDATE(), SYSDATETIME(), SYSDATETIMEOFFSET(), N'Romance Standard Time', N'Aleutian Standard Time');

-- convert a DATETIMEOFFSET to a DATETIME2 with a dynamic target time zone using the pair of functions
SELECT	
	f.ConvertedDateTime2,
	CAST(t.InputDateTimeOffset AT TIME ZONE t.TargetTimeZone AS DATETIME2) -- equivalent method
FROM @t t
OUTER APPLY dbo.TZGetOffsetsDTO(t.InputDateTimeOffset, t.TargetTimeZone) o
CROSS APPLY dbo.TZFormatDTO(t.InputDateTimeOffset, t.TargetTimeZone, o.OffsetMinutes, o.TargetOffsetMinutes) f;

-- convert a DATETIME to a DATETIMEOFFSET with fixed source and target time zones using the simple function
SELECT
	c.ConvertedDateTimeOffset,
	t.InputDateTime AT TIME ZONE N'Central Standard Time' AT TIME ZONE N'E. Africa Standard Time' -- equivalent method
FROM @t t
CROSS APPLY dbo.TZConvertDT(t.InputDateTime, N'Central Standard Time', N'E. Africa Standard Time') c;
```

# Setup

Executing the code from the latest release allows steps 1 - 4 to be skipped.

1. Create the `TimeZoneNames` table type from the other folder.
2. Create the `TimeZoneConversionHelper_CCI` and `TimeZoneConversionHelper_RS` tables from the tables folder.
3. Create the `RefreshTimeZoneConversionHelperTable` stored procedure from the procedures folder.
4. Create all nine functions from the functions folder.
    - Some environments benefit from customization of the functions. See step 8 for instructions.
5. By default, the `RefreshTimeZoneConversionHelperTable` stored procedure will populate data for all time zones for the past 30 years. Note that the functions are designed to return accurate results even for inputs that aren't mapped in the helper tables. Adjust the time period and time zones for the mapping if desired by passing explicit values for the input parameters.
6. Execute the `RefreshTimeZoneConversionHelperTable` stored procedure to populate the helper tables.
7. Schedule the `RefreshTimeZoneConversionHelperTable` stored procedure to run on a recurring basis. It is recommended to run the stored procedure daily a few hours after your typical time for applying Windows updates.
8. The functions support a variety of different inputs and scenarios. Consider customizing the functions to better meet your specific needs. For example:
   - You only need functions that support the data types that you use to store your data. For example, if you don't store any data in the `DATETIMEOFFSET` data type then you don't need the three functions that support that data type as an input.
   - If all of your data is stored in the same time zone then you may want create wrapper functions that hard code a value for the `@SourceTimeZoneName` parameters.
   - Don't create the simple version of the functions if you want developers to always use the better performing function pairs.

# Remarks

- The provided functions aim to reduce the CPU time required to perform time zone calculations only. If a query performance problem is caused by a poor cardinality estimate instead of a large number of `AT TIME ZONE` executions then changing to use these functions may not resolve the issue.
- Replacing `AT TIME ZONE` with these functions is equivalent to adding a join to the query for each function call. This will increase query plan complexity and in some cases may degrade performance for very complex queries.
- The functions work by looking for a match in the `TimeZoneConversionHelper` table. If no match is found then fallback code runs which calls the `AT TIME ZONE` operator. Query performance will improve as the percentage of matched inputs increases but the correct results should be returned even if there is no matching row in the table.
- The helper tables take up around 100 MB of space with default parameters for `RefreshTimeZoneConversionHelperTable`. The best way to reduce the size of the table is to call `RefreshTimeZoneConversionHelperTable` with the `@TimeZoneFilter` parameter set to the time zones relevant to your environment.
- The functions aim to mimic the behavior of the `AT TIME ZONE` operator. `AT TIME ZONE` uses a Windows mechanism which does not have all historical rule changes. The functions will also not reflect all historical rule changes, mostly prior to 2003. `AT TIME ZONE` also has rare phantom offset changes that last for one hour near the beginning of some calendar years for some time zones. The functions aim to replicate that behavior as well.
- The `RefreshTimeZoneConversionHelperTable` stored procedure uses a sampling technique that assumes that a time zone won't change its offset back and forth to the same value within any 24 hour period outside of a day before and after the start of a new year. As of October 2022, the shortest historical switch is 28 days for the Fiji Standard Time. If you feel that 24 hours is too generous of an assumption it is possible to change the value of the `@SampleHours` variable in `RefreshTimeZoneConversionHelperTable`.
- switch notes
-- index notes
-- CHECKSUM notes
