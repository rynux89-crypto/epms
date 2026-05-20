/*

  EPMS SQL All-In-One Runner



  Purpose

  - Run the EPMS SQL bundle directly in SSMS without SQLCMD mode.

  - Keep a single execution file for default setup plus optional sections.



  How to use

  1. Open this file in SSMS.

  2. Review the default execution section.

  3. Run the file as-is for the default schema/update path.

  4. If needed, uncomment specific optional sections and run them separately.



  Notes
  - This file is plain T-SQL text with embedded source scripts.
  - The original per-feature SQL sources are stored under docs/sql/src/.
  - Optional job/check scripts are kept inside block comments.
*/



PRINT '=== EPMS SQL All-In-One Runner: start ===';

GO



PRINT '--- 1. create_epms_schema.sql ---';

GO

/* ===== BEGIN create_epms_schema.sql ===== */

-- EPMS schema script generated from current local database


-- Generated: 2026-04-02 13:00:02


SET ANSI_NULLS ON;


SET QUOTED_IDENTIFIER ON;


GO


IF DB_ID(N'epms') IS NULL


BEGIN


    CREATE DATABASE [epms];


END


GO


USE [epms];


GO





/****** Object:  Table [dbo].[alarm_log]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[alarm_log](


	[alarm_id] [bigint] IDENTITY(1,1) NOT NULL,


	[meter_id] [int] NULL,


	[alarm_type] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[severity] [varchar](20) COLLATE Korean_Wansung_CI_AS NULL,


	[triggered_at] [datetime] NULL,


	[cleared_at] [datetime] NULL,


	[description] [text] COLLATE Korean_Wansung_CI_AS NULL,


	[rule_id] [int] NULL,


	[rule_code] [varchar](50) COLLATE Korean_Wansung_CI_AS NULL,


	[metric_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[source_token] [varchar](120) COLLATE Korean_Wansung_CI_AS NULL,


	[measured_value] [float] NULL,


	[operator] [varchar](10) COLLATE Korean_Wansung_CI_AS NULL,


	[threshold1] [float] NULL,


	[threshold2] [float] NULL,


PRIMARY KEY CLUSTERED


(


	[alarm_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]





SET ANSI_PADDING OFF


/****** Object:  Index [idx_alarm_meter_time]    Script Date: 2026-04-02 1:00:03 ******/


CREATE NONCLUSTERED INDEX [idx_alarm_meter_time] ON [dbo].[alarm_log]


(


	[meter_id] ASC,


	[triggered_at] DESC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


SET ANSI_PADDING ON





/****** Object:  Index [idx_alarm_severity]    Script Date: 2026-04-02 1:00:03 ******/


CREATE NONCLUSTERED INDEX [idx_alarm_severity] ON [dbo].[alarm_log]


(


	[severity] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO





/****** Object:  Table [dbo].[alarm_rule]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[alarm_rule](


	[rule_id] [int] IDENTITY(1,1) NOT NULL,


	[rule_code] [varchar](50) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[rule_name] [nvarchar](120) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[category] [varchar](30) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[target_scope] [varchar](20) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[metric_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[operator] [varchar](10) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[threshold1] [decimal](18, 6) NULL,


	[threshold2] [decimal](18, 6) NULL,


	[duration_sec] [int] NOT NULL,


	[hysteresis] [decimal](18, 6) NULL,


	[severity] [varchar](20) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[enabled] [bit] NOT NULL,


	[description] [nvarchar](500) COLLATE Korean_Wansung_CI_AS NULL,


	[created_at] [datetime2](7) NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


	[source_token] [varchar](120) COLLATE Korean_Wansung_CI_AS NULL,


	[message_template] [nvarchar](300) COLLATE Korean_Wansung_CI_AS NULL,


PRIMARY KEY CLUSTERED


(


	[rule_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


SET ANSI_PADDING ON





/****** Object:  Index [ux_alarm_rule_code]    Script Date: 2026-04-02 1:00:03 ******/


CREATE UNIQUE NONCLUSTERED INDEX [ux_alarm_rule_code] ON [dbo].[alarm_rule]


(


	[rule_code] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT ('METER') FOR [target_scope]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT ('>=') FOR [operator]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT ((0)) FOR [duration_sec]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT ('WARN') FOR [severity]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT (sysutcdatetime()) FOR [created_at]


ALTER TABLE [dbo].[alarm_rule] ADD  DEFAULT (sysutcdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[building_alias]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[building_alias](


	[alias_id] [int] IDENTITY(1,1) NOT NULL,


	[building_name] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[alias_keyword] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[is_active] [bit] NOT NULL,


	[created_at] [datetime2](0) NOT NULL,


	[updated_at] [datetime2](0) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[alias_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING ON





/****** Object:  Index [UX_building_alias_keyword]    Script Date: 2026-04-02 1:00:03 ******/


CREATE UNIQUE NONCLUSTERED INDEX [UX_building_alias_keyword] ON [dbo].[building_alias]


(


	[alias_keyword] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[building_alias] ADD  CONSTRAINT [DF_building_alias_is_active]  DEFAULT ((1)) FOR [is_active]


ALTER TABLE [dbo].[building_alias] ADD  CONSTRAINT [DF_building_alias_created_at]  DEFAULT (sysdatetime()) FOR [created_at]


ALTER TABLE [dbo].[building_alias] ADD  CONSTRAINT [DF_building_alias_updated_at]  DEFAULT (sysdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[daily_measurements]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[daily_measurements](

	[day_id] [bigint] IDENTITY(1,1) NOT NULL,

	[meter_id] [int] NULL,

	[measured_date] [date] NOT NULL,

	[avg_current] [float] NULL,

	[max_line_voltage] [float] NULL,

	[min_line_voltage] [float] NULL,

	[max_phase_voltage] [float] NULL,

	[min_phase_voltage] [float] NULL,

	[max_current] [float] NULL,

	[min_current] [float] NULL,

	[energy_consumed_kwh] [float] NULL,

PRIMARY KEY CLUSTERED

(


	[day_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





/****** Object:  Index [idx_daily_meter_date]    Script Date: 2026-04-02 1:00:03 ******/


CREATE UNIQUE NONCLUSTERED INDEX [idx_daily_meter_date] ON [dbo].[daily_measurements]


(


	[meter_id] ASC,


	[measured_date] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO





/****** Object:  Table [dbo].[device_events]    Script Date: 2026-04-02 1:00:03 ******/

SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

SET ANSI_PADDING ON

CREATE TABLE [dbo].[device_events](

	[event_id] [bigint] IDENTITY(1,1) NOT NULL,

	[meter_id] [int] NULL,

	[device_id] [int] NULL,

	[event_type] [varchar](50) COLLATE Korean_Wansung_CI_AS NULL,

	[event_time] [datetime] NOT NULL,

	[restored_time] [datetime] NULL,

	[severity] [varchar](20) COLLATE Korean_Wansung_CI_AS NULL,

	[description] [text] COLLATE Korean_Wansung_CI_AS NULL,

	[trip_count] [int] NULL,

	[outage_count] [int] NULL,

	[switch_count] [int] NULL,

	[downtime_minutes] [float] NULL,

	[duration_seconds] [int] NULL,

	[operating_time_minutes] [float] NULL,

PRIMARY KEY CLUSTERED

(

	[event_id] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]



SET ANSI_PADDING OFF

/****** Object:  Index [idx_device_event_time]    Script Date: 2026-04-02 1:00:03 ******/

CREATE NONCLUSTERED INDEX [idx_device_event_time] ON [dbo].[device_events]

(

	[device_id] ASC,

	[event_time] DESC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

SET ANSI_PADDING ON



/****** Object:  Index [idx_device_event_meter_time]    Script Date: 2026-04-09 3:00:00 ******/

CREATE NONCLUSTERED INDEX [idx_device_event_meter_time] ON [dbo].[device_events]

(

	[meter_id] ASC,

	[event_time] DESC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

SET ANSI_PADDING ON



/****** Object:  Index [idx_device_event_type]    Script Date: 2026-04-02 1:00:03 ******/

CREATE NONCLUSTERED INDEX [idx_device_event_type] ON [dbo].[device_events]

(

	[event_type] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

ALTER TABLE [dbo].[device_events] ADD  DEFAULT ((0)) FOR [trip_count]

ALTER TABLE [dbo].[device_events] ADD  DEFAULT ((0)) FOR [outage_count]

ALTER TABLE [dbo].[device_events] ADD  DEFAULT ((0)) FOR [switch_count]

GO


/****** Object:  Table [dbo].[devices]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[devices](


	[device_id] [int] IDENTITY(1,1) NOT NULL,


	[device_name] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[device_type] [varchar](50) COLLATE Korean_Wansung_CI_AS NULL,


	[location] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[panel_name] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[building_name] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[install_date] [date] NULL,


	[status] [varchar](20) COLLATE Korean_Wansung_CI_AS NULL,


	[remarks] [text] COLLATE Korean_Wansung_CI_AS NULL,


PRIMARY KEY CLUSTERED


(


	[device_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]





SET ANSI_PADDING OFF


/****** Object:  Index [idx_devices_id]    Script Date: 2026-04-02 1:00:03 ******/


CREATE UNIQUE NONCLUSTERED INDEX [idx_devices_id] ON [dbo].[devices]


(


	[device_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


SET ANSI_PADDING ON





/****** Object:  Index [idx_devices_location]    Script Date: 2026-04-02 1:00:03 ******/


CREATE NONCLUSTERED INDEX [idx_devices_location] ON [dbo].[devices]


(


	[location] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[devices] ADD  DEFAULT ('Active') FOR [status]


GO





/****** Object:  Table [dbo].[di_group_rule_map]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[di_group_rule_map](


	[group_rule_id] [int] IDENTITY(1,1) NOT NULL,


	[metric_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[match_mode] [varchar](20) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[count_threshold] [int] NULL,


	[enabled] [bit] NOT NULL,


	[description] [nvarchar](300) COLLATE Korean_Wansung_CI_AS NULL,


	[created_at] [datetime2](7) NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[group_rule_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


SET ANSI_PADDING ON





/****** Object:  Index [ux_di_group_rule_map_metric]    Script Date: 2026-04-02 1:00:03 ******/


CREATE UNIQUE NONCLUSTERED INDEX [ux_di_group_rule_map_metric] ON [dbo].[di_group_rule_map]


(


	[metric_key] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT ('ANY_ON') FOR [match_mode]


ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT (sysutcdatetime()) FOR [created_at]


ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT (sysutcdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[di_signal_group_map]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[di_signal_group_map](


	[group_map_id] [int] IDENTITY(1,1) NOT NULL,


	[group_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[metric_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[match_type] [varchar](30) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[match_value] [varchar](200) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[priority] [int] NOT NULL,


	[enabled] [bit] NOT NULL,


	[description] [nvarchar](300) COLLATE Korean_Wansung_CI_AS NULL,


	[created_at] [datetime2](7) NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[group_map_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


SET ANSI_PADDING ON





/****** Object:  Index [ux_di_signal_group_map_key]    Script Date: 2026-04-02 1:00:03 ******/


CREATE UNIQUE NONCLUSTERED INDEX [ux_di_signal_group_map_key] ON [dbo].[di_signal_group_map]


(


	[group_key] ASC,


	[metric_key] ASC,


	[match_type] ASC,


	[match_value] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[di_signal_group_map] ADD  DEFAULT ((100)) FOR [priority]


ALTER TABLE [dbo].[di_signal_group_map] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[di_signal_group_map] ADD  DEFAULT (sysutcdatetime()) FOR [created_at]


ALTER TABLE [dbo].[di_signal_group_map] ADD  DEFAULT (sysutcdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[flicker_measurements]    Script Date: 2026-04-02 1:00:03 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[flicker_measurements](


	[flicker_id] [bigint] IDENTITY(1,1) NOT NULL,


	[meter_id] [int] NULL,


	[measured_at] [datetime] NOT NULL,


	[flicker_pst] [float] NULL,


	[flicker_plt] [float] NULL,


PRIMARY KEY CLUSTERED


(


	[flicker_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





/****** Object:  Index [idx_flicker_measured_at]    Script Date: 2026-04-02 1:00:03 ******/


CREATE NONCLUSTERED INDEX [idx_flicker_measured_at] ON [dbo].[flicker_measurements]


(


	[measured_at] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


/****** Object:  Index [idx_flicker_meter_id]    Script Date: 2026-04-02 1:00:03 ******/


CREATE NONCLUSTERED INDEX [idx_flicker_meter_id] ON [dbo].[flicker_measurements]


(


	[meter_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO





/****** Object:  Table [dbo].[harmonic_measurements]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[harmonic_measurements](


	[harmonic_id] [bigint] IDENTITY(1,1) NOT NULL,


	[meter_id] [int] NULL,


	[measured_at] [datetime] NOT NULL,


	[thd_voltage_a] [float] NULL,


	[thd_voltage_b] [float] NULL,


	[thd_voltage_c] [float] NULL,


	[voltage_h3_a] [float] NULL,


	[voltage_h5_a] [float] NULL,


	[voltage_h7_a] [float] NULL,


	[voltage_h3_b] [float] NULL,


	[voltage_h5_b] [float] NULL,


	[voltage_h7_b] [float] NULL,


	[voltage_h3_c] [float] NULL,


	[voltage_h5_c] [float] NULL,


	[voltage_h7_c] [float] NULL,


	[thd_current_a] [float] NULL,


	[thd_current_b] [float] NULL,


	[thd_current_c] [float] NULL,


	[current_h3_a] [float] NULL,


	[current_h5_a] [float] NULL,


	[current_h7_a] [float] NULL,


	[current_h3_b] [float] NULL,


	[current_h5_b] [float] NULL,


	[current_h7_b] [float] NULL,


	[current_h3_c] [float] NULL,


	[current_h5_c] [float] NULL,


	[current_h7_c] [float] NULL,


	[voltage_h9_a] [float] NULL,


	[voltage_h11_a] [float] NULL,


	[voltage_h9_b] [float] NULL,


	[voltage_h11_b] [float] NULL,


	[voltage_h9_c] [float] NULL,


	[voltage_h11_c] [float] NULL,


	[current_h9_a] [float] NULL,


	[current_h11_a] [float] NULL,


	[current_h9_b] [float] NULL,


	[current_h11_b] [float] NULL,


	[current_h9_c] [float] NULL,


	[current_h11_c] [float] NULL,


PRIMARY KEY CLUSTERED


(


	[harmonic_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





GO





/****** Object:  Table [dbo].[measurements]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[measurements](


	[measurement_id] [bigint] IDENTITY(1,1) NOT NULL,


	[meter_id] [int] NULL,


	[measured_at] [datetime] NOT NULL,


	[voltage_ab] [float] NULL,


	[voltage_bc] [float] NULL,


	[voltage_ca] [float] NULL,


	[voltage_an] [float] NULL,


	[voltage_bn] [float] NULL,


	[voltage_cn] [float] NULL,


	[current_a] [float] NULL,


	[current_b] [float] NULL,


	[current_c] [float] NULL,


	[current_n] [float] NULL,


	[average_voltage] [float] NULL,


	[average_current] [float] NULL,


	[frequency] [float] NULL,


	[power_factor_a] [float] NULL,


	[power_factor_b] [float] NULL,


	[power_factor_c] [float] NULL,


	[active_power_a] [float] NULL,


	[active_power_b] [float] NULL,


	[active_power_c] [float] NULL,


	[active_power_total] [float] NULL,


	[reactive_power_a] [float] NULL,


	[reactive_power_b] [float] NULL,


	[reactive_power_c] [float] NULL,


	[reactive_power_total] [float] NULL,


	[apparent_power_a] [float] NULL,


	[apparent_power_b] [float] NULL,


	[apparent_power_c] [float] NULL,


	[apparent_power_total] [float] NULL,


	[energy_consumed_total] [float] NULL,


	[energy_generated_total] [float] NULL,


	[reactive_energy_total] [float] NULL,


	[apparent_energy_total] [float] NULL,


	[voltage_max] [float] NULL,


	[voltage_min] [float] NULL,


	[voltage_stddev] [float] NULL,


	[voltage_variation_rate] [float] NULL,


	[current_max] [float] NULL,


	[current_min] [float] NULL,


	[current_stddev] [float] NULL,


	[current_variation_rate] [float] NULL,


	[power_factor_avg] [float] NULL,


	[power_factor_min] [float] NULL,


	[active_power_avg] [float] NULL,


	[reactive_power_avg] [float] NULL,


	[apparent_power_avg] [float] NULL,


	[energy_consumed_delta] [float] NULL,


	[energy_generated_delta] [float] NULL,


	[voltage_unbalance_rate] [float] NULL,


	[harmonic_distortion_rate] [float] NULL,


	[quality_status] [varchar](50) COLLATE Korean_Wansung_CI_AS NULL,


	[voltage_phase_a] [float] NULL,


	[voltage_phase_b] [float] NULL,


	[voltage_phase_c] [float] NULL,


	[current_phase_a] [float] NULL,


	[current_phase_b] [float] NULL,


	[current_phase_c] [float] NULL,


	[max_power] [float] NULL,


	[power_factor] [float] NULL,


	[phase_voltage_avg] [float] NULL,


	[line_voltage_avg] [float] NULL,


PRIMARY KEY CLUSTERED


(


	[measurement_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


/****** Object:  Index [idx_measurements_id]    Script Date: 2026-04-02 1:00:04 ******/


CREATE UNIQUE NONCLUSTERED INDEX [idx_measurements_id] ON [dbo].[measurements]


(


	[measurement_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


/****** Object:  Index [idx_measurements_meter_time]    Script Date: 2026-04-02 1:00:04 ******/


CREATE NONCLUSTERED INDEX [idx_measurements_meter_time] ON [dbo].[measurements]


(


	[meter_id] ASC,


	[measured_at] DESC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO








/****** Object:  Table [dbo].[meter_tree]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[meter_tree](


	[relation_id] [bigint] IDENTITY(1,1) NOT NULL,


	[parent_meter_id] [int] NOT NULL,


	[child_meter_id] [int] NOT NULL,


	[is_active] [bit] NOT NULL,


	[sort_order] [int] NULL,


	[note] [nvarchar](400) COLLATE Korean_Wansung_CI_AS NULL,


	[created_at] [datetime2](7) NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[relation_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY],


 CONSTRAINT [UQ_meter_tree_parent_child] UNIQUE NONCLUSTERED


(


	[parent_meter_id] ASC,


	[child_meter_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





/****** Object:  Index [IX_meter_tree_child]    Script Date: 2026-04-02 1:00:04 ******/


CREATE NONCLUSTERED INDEX [IX_meter_tree_child] ON [dbo].[meter_tree]


(


	[child_meter_id] ASC,


	[is_active] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


/****** Object:  Index [IX_meter_tree_parent]    Script Date: 2026-04-02 1:00:04 ******/


CREATE NONCLUSTERED INDEX [IX_meter_tree_parent] ON [dbo].[meter_tree]


(


	[parent_meter_id] ASC,


	[is_active] ASC,


	[sort_order] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[meter_tree] ADD  CONSTRAINT [DF_meter_tree_active]  DEFAULT ((1)) FOR [is_active]


ALTER TABLE [dbo].[meter_tree] ADD  CONSTRAINT [DF_meter_tree_created]  DEFAULT (sysutcdatetime()) FOR [created_at]


ALTER TABLE [dbo].[meter_tree] ADD  CONSTRAINT [DF_meter_tree_updated]  DEFAULT (sysutcdatetime()) FOR [updated_at]


ALTER TABLE [dbo].[meter_tree]  WITH CHECK ADD  CONSTRAINT [CK_meter_tree_not_self] CHECK  (([parent_meter_id]<>[child_meter_id]))


ALTER TABLE [dbo].[meter_tree] CHECK CONSTRAINT [CK_meter_tree_not_self]


GO





/****** Object:  Table [dbo].[meters]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[meters](


	[meter_id] [int] IDENTITY(1,1) NOT NULL,


	[name] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[panel_name] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[building_name] [varchar](100) COLLATE Korean_Wansung_CI_AS NULL,


	[usage_type] [varchar](50) COLLATE Korean_Wansung_CI_AS NULL,


	[rated_voltage] [float] NULL,


	[rated_current] [float] NULL,


PRIMARY KEY CLUSTERED


(


	[meter_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


SET ANSI_PADDING ON





/****** Object:  Index [idx_meters_building_usage]    Script Date: 2026-04-02 1:00:04 ******/


CREATE NONCLUSTERED INDEX [idx_meters_building_usage] ON [dbo].[meters]


(


	[building_name] ASC,


	[usage_type] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


/****** Object:  Index [idx_meters_meter_id]    Script Date: 2026-04-02 1:00:04 ******/


CREATE UNIQUE NONCLUSTERED INDEX [idx_meters_meter_id] ON [dbo].[meters]


(


	[meter_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO





/****** Object:  Table [dbo].[metric_catalog]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[metric_catalog](


	[metric_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[display_name] [nvarchar](150) COLLATE Korean_Wansung_CI_AS NULL,


	[source_type] [varchar](20) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[enabled] [bit] NOT NULL,


	[created_at] [datetime2](7) NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[metric_key] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


ALTER TABLE [dbo].[metric_catalog] ADD  DEFAULT ('AI') FOR [source_type]


ALTER TABLE [dbo].[metric_catalog] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[metric_catalog] ADD  DEFAULT (sysutcdatetime()) FOR [created_at]


ALTER TABLE [dbo].[metric_catalog] ADD  DEFAULT (sysutcdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[metric_catalog_tag_map]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


SET ANSI_PADDING ON


CREATE TABLE [dbo].[metric_catalog_tag_map](


	[map_id] [int] IDENTITY(1,1) NOT NULL,


	[metric_key] [varchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[source_token] [varchar](120) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[sort_no] [int] NOT NULL,


	[enabled] [bit] NOT NULL,


	[created_at] [datetime2](7) NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[map_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING OFF


SET ANSI_PADDING ON





/****** Object:  Index [ix_metric_catalog_tag_map_metric_key]    Script Date: 2026-04-02 1:00:04 ******/


CREATE NONCLUSTERED INDEX [ix_metric_catalog_tag_map_metric_key] ON [dbo].[metric_catalog_tag_map]


(


	[metric_key] ASC,


	[enabled] ASC,


	[sort_no] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


SET ANSI_PADDING ON





/****** Object:  Index [ux_metric_catalog_tag_map_key_token]    Script Date: 2026-04-02 1:00:04 ******/


CREATE UNIQUE NONCLUSTERED INDEX [ux_metric_catalog_tag_map_key_token] ON [dbo].[metric_catalog_tag_map]


(


	[metric_key] ASC,


	[source_token] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[metric_catalog_tag_map] ADD  DEFAULT ((1)) FOR [sort_no]


ALTER TABLE [dbo].[metric_catalog_tag_map] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[metric_catalog_tag_map] ADD  DEFAULT (sysutcdatetime()) FOR [created_at]


ALTER TABLE [dbo].[metric_catalog_tag_map] ADD  DEFAULT (sysutcdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[monthly_measurements]    Script Date: 2026-04-02 1:00:04 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[monthly_measurements](

	[month_id] [bigint] IDENTITY(1,1) NOT NULL,

	[meter_id] [int] NULL,

	[measured_month] [date] NOT NULL,

	[avg_current] [float] NULL,

	[max_line_voltage] [float] NULL,

	[min_line_voltage] [float] NULL,

	[max_phase_voltage] [float] NULL,

	[min_phase_voltage] [float] NULL,

	[energy_consumed_kwh] [float] NULL,

PRIMARY KEY CLUSTERED

(


	[month_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





/****** Object:  Index [idx_monthly_meter_month]    Script Date: 2026-04-02 1:00:04 ******/


CREATE UNIQUE NONCLUSTERED INDEX [idx_monthly_meter_month] ON [dbo].[monthly_measurements]


(


	[meter_id] ASC,


	[measured_month] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO





/****** Object:  Table [dbo].[plc_ai_measurements_match]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_ai_measurements_match](


	[token] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[float_index] [int] NOT NULL,


	[float_registers] [int] NOT NULL,


	[measurement_column] [sysname] COLLATE Korean_Wansung_CI_AS NULL,


	[target_table] [nvarchar](64) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[is_supported] [bit] NOT NULL,


	[note] [nvarchar](400) COLLATE Korean_Wansung_CI_AS NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[token] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_ai_measurements_match] ADD  CONSTRAINT [DF_plc_ai_match_float_regs]  DEFAULT ((2)) FOR [float_registers]


ALTER TABLE [dbo].[plc_ai_measurements_match] ADD  CONSTRAINT [DF_plc_ai_match_target_table]  DEFAULT ('measurements') FOR [target_table]


ALTER TABLE [dbo].[plc_ai_measurements_match] ADD  CONSTRAINT [DF_plc_ai_match_updated]  DEFAULT (sysutcdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[plc_ai_samples]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_ai_samples](


	[id] [bigint] IDENTITY(1,1) NOT NULL,


	[measured_at] [datetime2](7) NOT NULL,


	[plc_id] [int] NULL,


	[plc_ip] [nvarchar](64) COLLATE Korean_Wansung_CI_AS NULL,


	[unit_id] [int] NULL,


	[meter_id] [int] NULL,


	[reg_address] [int] NOT NULL,


	[value_float] [float] NOT NULL,


	[byte_order] [nvarchar](10) COLLATE Korean_Wansung_CI_AS NULL,


	[quality] [nvarchar](16) COLLATE Korean_Wansung_CI_AS NOT NULL,


PRIMARY KEY CLUSTERED


(


	[id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_ai_samples] ADD  DEFAULT (sysdatetime()) FOR [measured_at]


ALTER TABLE [dbo].[plc_ai_samples] ADD  DEFAULT ('GOOD') FOR [quality]


GO





/****** Object:  Table [dbo].[plc_ai_write_task]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_ai_write_task](


	[task_id] [int] IDENTITY(1,1) NOT NULL,


	[plc_id] [int] NOT NULL,


	[meter_id] [int] NOT NULL,


	[start_address] [int] NOT NULL,


	[float_index] [int] NOT NULL,


	[byte_order] [nvarchar](10) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[write_value] [float] NOT NULL,


	[enabled] [bit] NOT NULL,


	[last_written_at] [datetime2](7) NULL,


	[last_error] [nvarchar](400) COLLATE Korean_Wansung_CI_AS NULL,


	[updated_at] [datetime2](7) NOT NULL,


	[value_source] [nvarchar](16) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[last_written_value] [float] NULL,


	[task_scope] [nvarchar](10) COLLATE Korean_Wansung_CI_AS NOT NULL,


PRIMARY KEY CLUSTERED


(


	[task_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_ai_write_task] ADD  DEFAULT ((0)) FOR [float_index]


ALTER TABLE [dbo].[plc_ai_write_task] ADD  DEFAULT ('ABCD') FOR [byte_order]


ALTER TABLE [dbo].[plc_ai_write_task] ADD  DEFAULT ((0)) FOR [write_value]


ALTER TABLE [dbo].[plc_ai_write_task] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[plc_ai_write_task] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


ALTER TABLE [dbo].[plc_ai_write_task] ADD  CONSTRAINT [DF_plc_ai_write_task_value_source]  DEFAULT ('MEASURED') FOR [value_source]


ALTER TABLE [dbo].[plc_ai_write_task] ADD  CONSTRAINT [DF_plc_ai_write_task_task_scope]  DEFAULT ('POINT') FOR [task_scope]


GO





/****** Object:  Table [dbo].[plc_config]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_config](


	[plc_id] [int] NOT NULL,


	[plc_ip] [nvarchar](64) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[plc_port] [int] NOT NULL,


	[unit_id] [int] NOT NULL,


	[polling_ms] [int] NOT NULL,


	[enabled] [bit] NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


	[insert_ms] [int] NOT NULL,


PRIMARY KEY CLUSTERED


(


	[plc_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_config] ADD  DEFAULT ((502)) FOR [plc_port]


ALTER TABLE [dbo].[plc_config] ADD  DEFAULT ((1)) FOR [unit_id]


ALTER TABLE [dbo].[plc_config] ADD  DEFAULT ((1000)) FOR [polling_ms]


ALTER TABLE [dbo].[plc_config] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[plc_config] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


ALTER TABLE [dbo].[plc_config] ADD  CONSTRAINT [DF_plc_config_insert_ms]  DEFAULT ((1000)) FOR [insert_ms]


GO





/****** Object:  Table [dbo].[plc_di_map]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_di_map](


	[di_map_id] [int] IDENTITY(1,1) NOT NULL,


	[plc_id] [int] NOT NULL,


	[point_id] [int] NOT NULL,


	[start_address] [int] NOT NULL,


	[bit_count] [int] NOT NULL,


	[enabled] [bit] NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[di_map_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_di_map] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[plc_di_map] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[plc_di_samples]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_di_samples](


	[id] [bigint] IDENTITY(1,1) NOT NULL,


	[measured_at] [datetime2](7) NOT NULL,


	[plc_id] [int] NULL,


	[plc_ip] [nvarchar](64) COLLATE Korean_Wansung_CI_AS NULL,


	[unit_id] [int] NULL,


	[point_id] [int] NULL,


	[di_address] [int] NOT NULL,


	[di_value] [int] NOT NULL,


	[quality] [nvarchar](16) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[bit_no] [int] NULL,


PRIMARY KEY CLUSTERED


(


	[id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_di_samples] ADD  DEFAULT (sysdatetime()) FOR [measured_at]


ALTER TABLE [dbo].[plc_di_samples] ADD  DEFAULT ('GOOD') FOR [quality]


GO





/****** Object:  Table [dbo].[plc_di_tag_map]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_di_tag_map](


	[tag_id] [int] IDENTITY(1,1) NOT NULL,


	[plc_id] [int] NOT NULL,


	[point_id] [int] NOT NULL,


	[di_address] [int] NOT NULL,


	[bit_no] [int] NOT NULL,


	[tag_name] [nvarchar](200) COLLATE Korean_Wansung_CI_AS NULL,


	[item_name] [nvarchar](200) COLLATE Korean_Wansung_CI_AS NULL,


	[panel_name] [nvarchar](200) COLLATE Korean_Wansung_CI_AS NULL,


	[enabled] [bit] NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[tag_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_di_tag_map] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[plc_di_tag_map] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[plc_meter_map]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_meter_map](


	[map_id] [int] IDENTITY(1,1) NOT NULL,


	[plc_id] [int] NOT NULL,


	[meter_id] [int] NOT NULL,


	[start_address] [int] NOT NULL,


	[float_count] [int] NOT NULL,


	[byte_order] [nvarchar](10) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[enabled] [bit] NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


	[metric_order] [nvarchar](1000) COLLATE Korean_Wansung_CI_AS NULL,


PRIMARY KEY CLUSTERED


(


	[map_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_meter_map] ADD  DEFAULT ('ABCD') FOR [byte_order]


ALTER TABLE [dbo].[plc_meter_map] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[plc_meter_map] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[plc_metric_random_range]    Script Date: 2026-04-02 1:00:05 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_metric_random_range](


	[metric_token] [nvarchar](50) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[min_value] [float] NOT NULL,


	[max_value] [float] NOT NULL,


	[enabled] [bit] NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[metric_token] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_metric_random_range] ADD  DEFAULT ((1)) FOR [enabled]


ALTER TABLE [dbo].[plc_metric_random_range] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[plc_write_control]    Script Date: 2026-04-02 1:00:06 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[plc_write_control](


	[id] [int] NOT NULL,


	[enabled] [bit] NOT NULL,


	[updated_at] [datetime2](7) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





ALTER TABLE [dbo].[plc_write_control] ADD  DEFAULT ((0)) FOR [enabled]


ALTER TABLE [dbo].[plc_write_control] ADD  DEFAULT (sysdatetime()) FOR [updated_at]


GO





/****** Object:  Table [dbo].[usage_type_alias]    Script Date: 2026-04-02 1:00:06 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[usage_type_alias](


	[alias_id] [int] IDENTITY(1,1) NOT NULL,


	[usage_type] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[alias_keyword] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,


	[is_active] [bit] NOT NULL,


	[created_at] [datetime2](0) NOT NULL,


	[updated_at] [datetime2](0) NOT NULL,


PRIMARY KEY CLUSTERED


(


	[alias_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





SET ANSI_PADDING ON





/****** Object:  Index [UX_usage_type_alias_keyword]    Script Date: 2026-04-02 1:00:06 ******/


CREATE UNIQUE NONCLUSTERED INDEX [UX_usage_type_alias_keyword] ON [dbo].[usage_type_alias]


(


	[alias_keyword] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


ALTER TABLE [dbo].[usage_type_alias] ADD  CONSTRAINT [DF_usage_type_alias_is_active]  DEFAULT ((1)) FOR [is_active]


ALTER TABLE [dbo].[usage_type_alias] ADD  CONSTRAINT [DF_usage_type_alias_created_at]  DEFAULT (sysdatetime()) FOR [created_at]


ALTER TABLE [dbo].[usage_type_alias] ADD  CONSTRAINT [DF_usage_type_alias_updated_at]  DEFAULT (sysdatetime()) FOR [updated_at]


GO








/****** Object:  Table [dbo].[yearly_measurements]    Script Date: 2026-04-02 1:00:06 ******/


SET ANSI_NULLS ON


SET QUOTED_IDENTIFIER ON


CREATE TABLE [dbo].[yearly_measurements](

	[year_id] [bigint] IDENTITY(1,1) NOT NULL,

	[meter_id] [int] NULL,

	[measured_year] [int] NOT NULL,

	[avg_current] [float] NULL,

	[max_line_voltage] [float] NULL,

	[min_line_voltage] [float] NULL,

	[max_phase_voltage] [float] NULL,

	[min_phase_voltage] [float] NULL,

	[energy_consumed_kwh] [float] NULL,

PRIMARY KEY CLUSTERED

(


	[year_id] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


) ON [PRIMARY]





/****** Object:  Index [idx_yearly_meter_year]    Script Date: 2026-04-02 1:00:06 ******/


CREATE UNIQUE NONCLUSTERED INDEX [idx_yearly_meter_year] ON [dbo].[yearly_measurements]


(


	[meter_id] ASC,


	[measured_year] ASC


)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]


GO





-- Foreign keys


ALTER TABLE [dbo].[alarm_log]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO





ALTER TABLE [dbo].[daily_measurements]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO





ALTER TABLE [dbo].[device_events]  WITH CHECK ADD  CONSTRAINT [FK_device_events_meters_meter_id] FOREIGN KEY([device_id])


REFERENCES [dbo].[meters] ([meter_id])


ALTER TABLE [dbo].[device_events] CHECK CONSTRAINT [FK_device_events_meters_meter_id]


GO








ALTER TABLE [dbo].[device_events]  WITH CHECK ADD  CONSTRAINT [FK_device_events_meter_id] FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


ALTER TABLE [dbo].[device_events] CHECK CONSTRAINT [FK_device_events_meter_id]


GO





ALTER TABLE [dbo].[flicker_measurements]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO





ALTER TABLE [dbo].[harmonic_measurements]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO





ALTER TABLE [dbo].[measurements]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO





ALTER TABLE [dbo].[meter_tree]  WITH CHECK ADD  CONSTRAINT [FK_meter_tree_child] FOREIGN KEY([child_meter_id])


REFERENCES [dbo].[meters] ([meter_id])


ALTER TABLE [dbo].[meter_tree] CHECK CONSTRAINT [FK_meter_tree_child]


GO





ALTER TABLE [dbo].[meter_tree]  WITH CHECK ADD  CONSTRAINT [FK_meter_tree_parent] FOREIGN KEY([parent_meter_id])


REFERENCES [dbo].[meters] ([meter_id])


ALTER TABLE [dbo].[meter_tree] CHECK CONSTRAINT [FK_meter_tree_parent]


GO





ALTER TABLE [dbo].[monthly_measurements]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO








ALTER TABLE [dbo].[yearly_measurements]  WITH CHECK ADD FOREIGN KEY([meter_id])


REFERENCES [dbo].[meters] ([meter_id])


GO








-- ============================================================


-- Views


-- ============================================================





IF OBJECT_ID(N'[dbo].[vw_alarm_log]', N'V') IS NOT NULL


    DROP VIEW [dbo].[vw_alarm_log];


GO


CREATE VIEW vw_alarm_log AS


SELECT


    m.meter_id,


    m.name AS meter_name,


    m.panel_name,


    m.building_name,


    m.usage_type,





    a.alarm_id,


    a.alarm_type,


    a.severity,


    a.triggered_at,


    a.cleared_at,


    a.description


FROM meters m


INNER JOIN alarm_log a ON m.meter_id = a.meter_id;


GO





IF OBJECT_ID(N'[dbo].[vw_device_event_log]', N'V') IS NOT NULL


    DROP VIEW [dbo].[vw_device_event_log];


GO


CREATE VIEW vw_device_event_log AS


SELECT


    COALESCE(e.meter_id, e.device_id) AS meter_id,


    m.name AS meter_name,


    m.panel_name,


    m.building_name,


    m.usage_type,


    e.event_id,


    e.event_type,


    e.event_time,


    e.restored_time,


    e.severity,


    e.description,


    e.trip_count,


    e.outage_count,


    e.switch_count,


    e.downtime_minutes,


    e.duration_seconds,


    e.operating_time_minutes


FROM device_events e


LEFT JOIN meters m ON m.meter_id = COALESCE(e.meter_id, e.device_id);


GO





IF OBJECT_ID(N'[dbo].[vw_flicker_with_meter]', N'V') IS NOT NULL


    DROP VIEW [dbo].[vw_flicker_with_meter];


GO


CREATE VIEW vw_flicker_with_meter AS


SELECT


m.meter_id,


    m.name,


m.panel_name,


    m.building_name,


    m.usage_type,


f.flicker_id,


    f.measured_at,


    f.flicker_pst,


    f.flicker_plt


FROM flicker_measurements f


JOIN meters m ON f.meter_id = m.meter_id;


GO





IF OBJECT_ID(N'[dbo].[vw_harmonic_measurements]', N'V') IS NOT NULL


    DROP VIEW [dbo].[vw_harmonic_measurements];


GO


CREATE VIEW dbo.vw_harmonic_measurements


AS


SELECT  m.meter_id, m.name AS meter_name, m.panel_name, m.building_name, m.usage_type, hm.harmonic_id, hm.measured_at, hm.thd_voltage_a, hm.thd_voltage_b, hm.thd_voltage_c,


               hm.voltage_h3_a, hm.voltage_h5_a, hm.voltage_h7_a, hm.voltage_h3_b, hm.voltage_h5_b, hm.voltage_h7_b, hm.voltage_h3_c, hm.voltage_h5_c, hm.voltage_h7_c, hm.thd_current_a,


               hm.thd_current_b, hm.thd_current_c, hm.current_h3_a, hm.current_h5_a, hm.current_h7_a, hm.current_h3_b, hm.current_h5_b, hm.current_h7_b, hm.current_h3_c, hm.current_h5_c,


               hm.current_h7_c, hm.voltage_h9_a, hm.voltage_h11_a, hm.voltage_h9_b, hm.voltage_h11_b, hm.voltage_h9_c, hm.voltage_h11_c, hm.current_h9_a, hm.current_h11_a, hm.current_h9_b,


               hm.current_h11_b, hm.current_h9_c, hm.current_h11_c


FROM     dbo.meters AS m INNER JOIN


               dbo.harmonic_measurements AS hm ON m.meter_id = hm.meter_id


GO





IF OBJECT_ID(N'[dbo].[vw_meter_measurements]', N'V') IS NOT NULL


    DROP VIEW [dbo].[vw_meter_measurements];


GO


CREATE VIEW vw_meter_measurements AS


SELECT


    m.meter_id,


    m.name AS meter_name,


    m.panel_name,


    m.building_name,


    m.usage_type,





    ms.measurement_id,


    ms.measured_at,





    -- ?�압


    ms.voltage_ab, ms.voltage_bc, ms.voltage_ca,


    ms.voltage_an, ms.voltage_bn, ms.voltage_cn,





    -- ?�류


    ms.current_a, ms.current_b, ms.current_c, ms.current_n,





    -- ?�균�?

    ms.average_voltage,


    ms.average_current,





    -- ??�� �?주파??

    ms.frequency,


    ms.power_factor,


    ms.power_factor_a, ms.power_factor_b, ms.power_factor_c,





    -- ?�력


    ms.active_power_total,


    ms.reactive_power_total,


    ms.apparent_power_total,


    ms.max_power,





    -- ?�너지


    ms.energy_consumed_total,


    ms.energy_generated_total,





    -- ?�략??

    ms.voltage_max,


    ms.voltage_min,


    ms.voltage_stddev,


    ms.voltage_variation_rate,


    ms.energy_generated_delta,





    -- ?�질 지??

    ms.voltage_unbalance_rate,


    ms.harmonic_distortion_rate,


    ms.quality_status,


    -- ?�상�?

    ms.voltage_phase_a, ms.voltage_phase_b, ms.voltage_phase_c,


    ms.current_phase_a, ms.current_phase_b, ms. current_phase_c





FROM meters m


INNER JOIN measurements ms ON m.meter_id = ms.meter_id;


GO







IF OBJECT_ID(N'[dbo].[vw_daily_measurements]', N'V') IS NOT NULL

    DROP VIEW [dbo].[vw_daily_measurements];

GO

CREATE VIEW [dbo].[vw_daily_measurements]

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    d.day_id,

    d.measured_date,

    d.avg_current,

    d.max_voltage,

    d.min_voltage,

    d.max_current,

    d.min_current,

    d.energy_consumed_kwh,

    d.voltage_unbalance_rate,

    d.harmonic_distortion_rate

FROM dbo.daily_measurements d

INNER JOIN dbo.meters m ON m.meter_id = d.meter_id;

GO



IF OBJECT_ID(N'[dbo].[vw_monthly_measurements]', N'V') IS NOT NULL

    DROP VIEW [dbo].[vw_monthly_measurements];

GO

CREATE VIEW [dbo].[vw_monthly_measurements]

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    mm.month_id,

    mm.measured_month,

    mm.avg_current,

    mm.max_voltage,

    mm.min_voltage,

    mm.energy_consumed_kwh,

    mm.voltage_unbalance_rate,

    mm.harmonic_distortion_rate

FROM dbo.monthly_measurements mm

INNER JOIN dbo.meters m ON m.meter_id = mm.meter_id;

GO



IF OBJECT_ID(N'[dbo].[vw_yearly_measurements]', N'V') IS NOT NULL

    DROP VIEW [dbo].[vw_yearly_measurements];

GO

CREATE VIEW [dbo].[vw_yearly_measurements]

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    y.year_id,

    y.measured_year,

    y.avg_current,

    y.max_voltage,

    y.min_voltage,

    y.energy_consumed_kwh,

    y.voltage_unbalance_rate,

    y.harmonic_distortion_rate

FROM dbo.yearly_measurements y

INNER JOIN dbo.meters m ON m.meter_id = y.meter_id;

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'[dbo].[harmonic_measurements]')

      AND name = N'IX_harmonic_measurements_meter_time'

)

BEGIN

    CREATE NONCLUSTERED INDEX [IX_harmonic_measurements_meter_time] ON [dbo].[harmonic_measurements]

    (

        [meter_id] ASC,

        [measured_at] DESC

    ) ON [PRIMARY];

END

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'[dbo].[plc_ai_samples]')

      AND name = N'IX_plc_ai_samples_plc_meter_measured_reg'

)

BEGIN

    CREATE NONCLUSTERED INDEX [IX_plc_ai_samples_plc_meter_measured_reg] ON [dbo].[plc_ai_samples]

    (

        [plc_id] ASC,

        [meter_id] ASC,

        [measured_at] DESC,

        [reg_address] ASC

    )

    INCLUDE ([value_float], [byte_order], [quality]) ON [PRIMARY];

END

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'[dbo].[plc_ai_samples]')

      AND name = N'IX_plc_ai_samples_meter_reg_measured_at'

)

BEGIN

    CREATE NONCLUSTERED INDEX [IX_plc_ai_samples_meter_reg_measured_at] ON [dbo].[plc_ai_samples]

    (

        [meter_id] ASC,

        [reg_address] ASC,

        [measured_at] DESC

    )

    INCLUDE ([value_float]) ON [PRIMARY];

END

GO



/****** Object:  Table [dbo].[plc_ai_mapping_master]    Script Date: 2026-04-03 9:00:00 ******/

SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[plc_ai_mapping_master](

	[plc_id] [int] NOT NULL,

	[meter_id] [int] NOT NULL,

	[float_index] [int] NOT NULL,

	[token] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,

	[reg_address] [int] NOT NULL,

	[byte_order] [nvarchar](10) COLLATE Korean_Wansung_CI_AS NOT NULL,

	[measurement_column] [nvarchar](128) COLLATE Korean_Wansung_CI_AS NULL,

	[target_table] [nvarchar](64) COLLATE Korean_Wansung_CI_AS NOT NULL,

	[db_insert_yn] [bit] NOT NULL,

	[enabled] [bit] NOT NULL,

	[note] [nvarchar](400) COLLATE Korean_Wansung_CI_AS NULL,

	[updated_at] [datetime2](7) NOT NULL,

PRIMARY KEY CLUSTERED

(

	[plc_id] ASC,

	[meter_id] ASC,

	[float_index] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

) ON [PRIMARY]

GO



ALTER TABLE [dbo].[plc_ai_mapping_master] ADD  CONSTRAINT [DF_plc_ai_mapping_master_byte_order]  DEFAULT ('ABCD') FOR [byte_order]

GO

ALTER TABLE [dbo].[plc_ai_mapping_master] ADD  CONSTRAINT [DF_plc_ai_mapping_master_target_table]  DEFAULT ('measurements') FOR [target_table]

GO

ALTER TABLE [dbo].[plc_ai_mapping_master] ADD  CONSTRAINT [DF_plc_ai_mapping_master_db_insert]  DEFAULT ((1)) FOR [db_insert_yn]

GO

ALTER TABLE [dbo].[plc_ai_mapping_master] ADD  CONSTRAINT [DF_plc_ai_mapping_master_enabled]  DEFAULT ((1)) FOR [enabled]

GO

ALTER TABLE [dbo].[plc_ai_mapping_master] ADD  CONSTRAINT [DF_plc_ai_mapping_master_updated]  DEFAULT (sysutcdatetime()) FOR [updated_at]

GO



SET ANSI_PADDING ON

GO



/****** Object:  Index [IX_plc_ai_mapping_master_token_idx]    Script Date: 2026-04-03 9:00:00 ******/

CREATE NONCLUSTERED INDEX [IX_plc_ai_mapping_master_token_idx] ON [dbo].[plc_ai_mapping_master]

(

	[token] ASC,

	[float_index] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO



/****** Object:  Index [IX_plc_ai_mapping_master_meter_addr]    Script Date: 2026-04-03 9:00:00 ******/

CREATE NONCLUSTERED INDEX [IX_plc_ai_mapping_master_meter_addr] ON [dbo].[plc_ai_mapping_master]

(

	[plc_id] ASC,

	[meter_id] ASC,

	[reg_address] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO



/****** Object:  Table [dbo].[plc_di_mapping_master]    Script Date: 2026-04-03 9:00:00 ******/

SET ANSI_NULLS ON

SET QUOTED_IDENTIFIER ON

CREATE TABLE [dbo].[plc_di_mapping_master](

	[plc_id] [int] NOT NULL,

	[point_id] [int] NOT NULL,

	[di_address] [int] NOT NULL,

	[bit_no] [int] NOT NULL,

	[meter_id] [int] NULL,

	[tag_name] [nvarchar](255) COLLATE Korean_Wansung_CI_AS NULL,

	[item_name] [nvarchar](255) COLLATE Korean_Wansung_CI_AS NULL,

	[panel_name] [nvarchar](255) COLLATE Korean_Wansung_CI_AS NULL,

	[enabled] [bit] NOT NULL,

	[note] [nvarchar](400) COLLATE Korean_Wansung_CI_AS NULL,

	[updated_at] [datetime2](7) NOT NULL,

PRIMARY KEY CLUSTERED

(

	[plc_id] ASC,

	[point_id] ASC,

	[di_address] ASC,

	[bit_no] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

) ON [PRIMARY]

GO



ALTER TABLE [dbo].[plc_di_mapping_master] ADD  CONSTRAINT [DF_plc_di_mapping_master_enabled]  DEFAULT ((1)) FOR [enabled]

GO

ALTER TABLE [dbo].[plc_di_mapping_master] ADD  CONSTRAINT [DF_plc_di_mapping_master_updated]  DEFAULT (sysutcdatetime()) FOR [updated_at]

GO



SET ANSI_PADDING ON

GO



/****** Object:  Index [IX_plc_di_mapping_master_addr]    Script Date: 2026-04-03 9:00:00 ******/

CREATE NONCLUSTERED INDEX [IX_plc_di_mapping_master_addr] ON [dbo].[plc_di_mapping_master]

(

	[plc_id] ASC,

	[di_address] ASC,

	[bit_no] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO



/****** Object:  Index [IX_plc_di_mapping_master_panel]    Script Date: 2026-04-03 9:00:00 ******/

CREATE NONCLUSTERED INDEX [IX_plc_di_mapping_master_panel] ON [dbo].[plc_di_mapping_master]

(

	[panel_name] ASC,

	[item_name] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO



/****** Object:  Index [IX_plc_di_mapping_master_meter]    Script Date: 2026-04-09 3:00:00 ******/

CREATE NONCLUSTERED INDEX [IX_plc_di_mapping_master_meter] ON [dbo].[plc_di_mapping_master]

(

	[meter_id] ASC,

	[plc_id] ASC,

	[point_id] ASC,

	[di_address] ASC,

	[bit_no] ASC

)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]

GO



ALTER TABLE [dbo].[plc_di_mapping_master]  WITH NOCHECK ADD  CONSTRAINT [FK_plc_di_mapping_master_meter] FOREIGN KEY([meter_id])

REFERENCES [dbo].[meters] ([meter_id])

GO



/*

After seeding plc_di_mapping_master rows on a live system, run:

  docs/sql/src/migrate_to_meter_centric_di.sql

  docs/sql/src/seed_di_virtual_meters.sql

The second script creates DI-only representative meters for logical DI groups

that do not correspond to an existing physical power meter.

*/


/* Aggregate measurements schema sync with dbo.measurements */

IF COL_LENGTH('dbo.daily_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.daily_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.daily_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.daily_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.daily_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.daily_measurements ADD reactive_energy_kvarh FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD reactive_energy_kvarh FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD reactive_energy_kvarh FLOAT NULL;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_daily_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.daily_measurements AS t

    USING (

        SELECT

            meter_id,

            CAST(measured_at AS DATE) AS measured_date,

            AVG(average_current) AS avg_current,

            MAX(voltage_max) AS max_voltage,

            MIN(voltage_min) AS min_voltage,

            MAX(current_max) AS max_current,

            MIN(current_min) AS min_current,

            MAX(energy_consumed_total) - MIN(energy_consumed_total) AS energy_consumed_kwh,

            AVG(line_voltage_avg) AS line_voltage_avg,

            AVG(phase_voltage_avg) AS phase_voltage_avg,

            AVG(power_factor) AS power_factor,

            MAX(max_power) AS max_power,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements

        WHERE measured_at >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))

        GROUP BY meter_id, CAST(measured_at AS DATE)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_date = s.measured_date)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_voltage = s.max_voltage,

            min_voltage = s.min_voltage,

            max_current = s.max_current,

            min_current = s.min_current,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_date,

            avg_current,

            max_voltage, min_voltage, max_current, min_current,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_date,

            s.avg_current,

            s.max_voltage, s.min_voltage, s.max_current, s.min_current,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



IF OBJECT_ID('dbo.hourly_measurements', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.hourly_measurements (

        hour_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,

        meter_id INT NULL,

        measured_hour DATETIME NOT NULL,

        avg_current FLOAT NULL,

        max_voltage FLOAT NULL,

        min_voltage FLOAT NULL,

        max_current FLOAT NULL,

        min_current FLOAT NULL,

        energy_consumed_kwh FLOAT NULL,

        line_voltage_avg FLOAT NULL,

        phase_voltage_avg FLOAT NULL,

        power_factor FLOAT NULL,

        max_power FLOAT NULL,

        reactive_energy_kvarh FLOAT NULL,



    );

END;

GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.hourly_measurements') AND name = 'idx_hourly_meter_hour')

    CREATE UNIQUE NONCLUSTERED INDEX idx_hourly_meter_hour ON dbo.hourly_measurements (meter_id, measured_hour);

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.foreign_keys

    WHERE name = 'FK_hourly_measurements_meter'

      AND parent_object_id = OBJECT_ID('dbo.hourly_measurements')

)

BEGIN

    ALTER TABLE dbo.hourly_measurements WITH CHECK

        ADD CONSTRAINT FK_hourly_measurements_meter FOREIGN KEY (meter_id)

        REFERENCES dbo.meters(meter_id);

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_hourly_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.hourly_measurements AS t

    USING (

        SELECT

            meter_id,

            DATEADD(HOUR, DATEDIFF(HOUR, 0, measured_at), 0) AS measured_hour,

            AVG(average_current) AS avg_current,

            MAX(voltage_max) AS max_voltage,

            MIN(voltage_min) AS min_voltage,

            MAX(current_max) AS max_current,

            MIN(current_min) AS min_current,

            MAX(energy_consumed_total) - MIN(energy_consumed_total) AS energy_consumed_kwh,

            AVG(line_voltage_avg) AS line_voltage_avg,

            AVG(phase_voltage_avg) AS phase_voltage_avg,

            AVG(power_factor) AS power_factor,

            MAX(max_power) AS max_power,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements

        WHERE measured_at >= DATEADD(DAY, -2, GETDATE())

        GROUP BY meter_id, DATEADD(HOUR, DATEDIFF(HOUR, 0, measured_at), 0)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_hour = s.measured_hour)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_voltage = s.max_voltage,

            min_voltage = s.min_voltage,

            max_current = s.max_current,

            min_current = s.min_current,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_hour,

            avg_current,

            max_voltage, min_voltage, max_current, min_current,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_hour,

            s.avg_current,

            s.max_voltage, s.min_voltage, s.max_current, s.min_current,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_monthly_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.monthly_measurements AS t

    USING (

        SELECT

            meter_id,

            DATEFROMPARTS(YEAR(measured_at), MONTH(measured_at), 1) AS measured_month,

            AVG(average_current) AS avg_current,

            MAX(voltage_max) AS max_voltage,

            MIN(voltage_min) AS min_voltage,

            MAX(energy_consumed_total) - MIN(energy_consumed_total) AS energy_consumed_kwh,

            AVG(line_voltage_avg) AS line_voltage_avg,

            AVG(phase_voltage_avg) AS phase_voltage_avg,

            AVG(power_factor) AS power_factor,

            MAX(max_power) AS max_power,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements

        WHERE measured_at >= DATEADD(MONTH, -1, GETDATE())

        GROUP BY meter_id, YEAR(measured_at), MONTH(measured_at)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_month = s.measured_month)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_voltage = s.max_voltage,

            min_voltage = s.min_voltage,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_month,

            avg_current,

            max_voltage, min_voltage,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_month,

            s.avg_current,

            s.max_voltage, s.min_voltage,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_yearly_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.yearly_measurements AS t

    USING (

        SELECT

            meter_id,

            YEAR(measured_at) AS measured_year,

            AVG(average_current) AS avg_current,

            MAX(voltage_max) AS max_voltage,

            MIN(voltage_min) AS min_voltage,

            MAX(energy_consumed_total) - MIN(energy_consumed_total) AS energy_consumed_kwh,

            AVG(line_voltage_avg) AS line_voltage_avg,

            AVG(phase_voltage_avg) AS phase_voltage_avg,

            AVG(power_factor) AS power_factor,

            MAX(max_power) AS max_power,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh,

            MAX(reactive_energy_total) - MIN(reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements

        WHERE measured_at >= DATEADD(YEAR, -1, GETDATE())

        GROUP BY meter_id, YEAR(measured_at)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_year = s.measured_year)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_voltage = s.max_voltage,

            min_voltage = s.min_voltage,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_year,

            avg_current,

            max_voltage, min_voltage,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_year,

            s.avg_current,

            s.max_voltage, s.min_voltage,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER VIEW dbo.vw_daily_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    d.day_id,

    d.measured_date,

    d.avg_current,

    d.max_voltage,

    d.min_voltage,

    d.max_current,

    d.min_current,

    d.energy_consumed_kwh,

    d.reactive_energy_kvarh,

    d.line_voltage_avg,

    d.phase_voltage_avg,

    d.power_factor,

    d.max_power

FROM dbo.daily_measurements d

INNER JOIN dbo.meters m ON m.meter_id = d.meter_id;

GO



CREATE OR ALTER VIEW dbo.vw_hourly_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    h.hour_id,

    h.measured_hour,

    h.avg_current,

    h.max_voltage,

    h.min_voltage,

    h.max_current,

    h.min_current,

    h.energy_consumed_kwh,

    h.reactive_energy_kvarh,

    h.line_voltage_avg,

    h.phase_voltage_avg,

    h.power_factor,

    h.max_power

FROM dbo.hourly_measurements h

INNER JOIN dbo.meters m ON m.meter_id = h.meter_id;

GO



CREATE OR ALTER VIEW dbo.vw_monthly_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    mm.month_id,

    mm.measured_month,

    mm.avg_current,

    mm.max_voltage,

    mm.min_voltage,

    mm.energy_consumed_kwh,

    mm.reactive_energy_kvarh,

    mm.line_voltage_avg,

    mm.phase_voltage_avg,

    mm.power_factor,

    mm.max_power

FROM dbo.monthly_measurements mm

INNER JOIN dbo.meters m ON m.meter_id = mm.meter_id;

GO



CREATE OR ALTER VIEW dbo.vw_yearly_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    y.year_id,

    y.measured_year,

    y.avg_current,

    y.max_voltage,

    y.min_voltage,

    y.energy_consumed_kwh,

    y.reactive_energy_kvarh,

    y.line_voltage_avg,

    y.phase_voltage_avg,

    y.power_factor,

    y.max_power

FROM dbo.yearly_measurements y

INNER JOIN dbo.meters m ON m.meter_id = y.meter_id;

GO

/* ===== END create_epms_schema.sql ===== */



PRINT '--- 2. update_aggregate_measurements_schema.sql ---';

GO

/* ===== BEGIN update_aggregate_measurements_schema.sql ===== */

SET NOCOUNT ON;

SET ANSI_NULLS ON;

SET QUOTED_IDENTIFIER ON;

GO



/* ---------------------------------------------------------------------------

   Aggregate measurements schema sync with dbo.measurements



   Purpose

   - Keep daily/monthly/yearly aggregate tables aligned with newer columns added

     to dbo.measurements.

   - Preserve existing columns for backward compatibility.

--------------------------------------------------------------------------- */



IF COL_LENGTH('dbo.daily_measurements', 'avg_voltage') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN avg_voltage;

IF COL_LENGTH('dbo.daily_measurements', 'avg_power_factor') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN avg_power_factor;

IF COL_LENGTH('dbo.daily_measurements', 'energy_generated_kwh') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN energy_generated_kwh;

IF COL_LENGTH('dbo.daily_measurements', 'apparent_energy_kvah') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN apparent_energy_kvah;

IF COL_LENGTH('dbo.daily_measurements', 'max_voltage') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN max_voltage;

IF COL_LENGTH('dbo.daily_measurements', 'min_voltage') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN min_voltage;

IF COL_LENGTH('dbo.daily_measurements', 'voltage_unbalance_rate') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN voltage_unbalance_rate;

IF COL_LENGTH('dbo.daily_measurements', 'harmonic_distortion_rate') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN harmonic_distortion_rate;

IF COL_LENGTH('dbo.daily_measurements', 'current_variation_rate') IS NOT NULL

    ALTER TABLE dbo.daily_measurements DROP COLUMN current_variation_rate;

IF COL_LENGTH('dbo.monthly_measurements', 'avg_voltage') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN avg_voltage;

IF COL_LENGTH('dbo.monthly_measurements', 'avg_power_factor') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN avg_power_factor;

IF COL_LENGTH('dbo.monthly_measurements', 'energy_generated_kwh') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN energy_generated_kwh;

IF COL_LENGTH('dbo.monthly_measurements', 'apparent_energy_kvah') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN apparent_energy_kvah;

IF COL_LENGTH('dbo.monthly_measurements', 'max_voltage') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN max_voltage;

IF COL_LENGTH('dbo.monthly_measurements', 'min_voltage') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN min_voltage;

IF COL_LENGTH('dbo.monthly_measurements', 'voltage_unbalance_rate') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN voltage_unbalance_rate;

IF COL_LENGTH('dbo.monthly_measurements', 'harmonic_distortion_rate') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN harmonic_distortion_rate;

IF COL_LENGTH('dbo.monthly_measurements', 'current_variation_rate') IS NOT NULL

    ALTER TABLE dbo.monthly_measurements DROP COLUMN current_variation_rate;

IF COL_LENGTH('dbo.yearly_measurements', 'avg_voltage') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN avg_voltage;

IF COL_LENGTH('dbo.yearly_measurements', 'avg_power_factor') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN avg_power_factor;

IF COL_LENGTH('dbo.yearly_measurements', 'energy_generated_kwh') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN energy_generated_kwh;

IF COL_LENGTH('dbo.yearly_measurements', 'apparent_energy_kvah') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN apparent_energy_kvah;

IF COL_LENGTH('dbo.yearly_measurements', 'max_voltage') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN max_voltage;

IF COL_LENGTH('dbo.yearly_measurements', 'min_voltage') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN min_voltage;

IF COL_LENGTH('dbo.yearly_measurements', 'voltage_unbalance_rate') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN voltage_unbalance_rate;

IF COL_LENGTH('dbo.yearly_measurements', 'harmonic_distortion_rate') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN harmonic_distortion_rate;

IF COL_LENGTH('dbo.yearly_measurements', 'current_variation_rate') IS NOT NULL

    ALTER TABLE dbo.yearly_measurements DROP COLUMN current_variation_rate;

IF COL_LENGTH('dbo.hourly_measurements', 'avg_voltage') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN avg_voltage;

IF COL_LENGTH('dbo.hourly_measurements', 'avg_power_factor') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN avg_power_factor;

IF COL_LENGTH('dbo.hourly_measurements', 'energy_generated_kwh') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN energy_generated_kwh;

IF COL_LENGTH('dbo.hourly_measurements', 'apparent_energy_kvah') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN apparent_energy_kvah;

IF COL_LENGTH('dbo.hourly_measurements', 'max_voltage') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN max_voltage;

IF COL_LENGTH('dbo.hourly_measurements', 'min_voltage') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN min_voltage;

IF COL_LENGTH('dbo.hourly_measurements', 'voltage_unbalance_rate') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN voltage_unbalance_rate;

IF COL_LENGTH('dbo.hourly_measurements', 'harmonic_distortion_rate') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN harmonic_distortion_rate;

IF COL_LENGTH('dbo.hourly_measurements', 'current_variation_rate') IS NOT NULL

    ALTER TABLE dbo.hourly_measurements DROP COLUMN current_variation_rate;

GO



IF COL_LENGTH('dbo.daily_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.daily_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.daily_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'max_line_voltage') IS NULL

    ALTER TABLE dbo.daily_measurements ADD max_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'min_line_voltage') IS NULL

    ALTER TABLE dbo.daily_measurements ADD min_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'max_phase_voltage') IS NULL

    ALTER TABLE dbo.daily_measurements ADD max_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'min_phase_voltage') IS NULL

    ALTER TABLE dbo.daily_measurements ADD min_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.daily_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.daily_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.daily_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.daily_measurements ADD reactive_energy_kvarh FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'max_line_voltage') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD max_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'min_line_voltage') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD min_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'max_phase_voltage') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD max_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'min_phase_voltage') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD min_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.monthly_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.monthly_measurements ADD reactive_energy_kvarh FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'max_line_voltage') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD max_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'min_line_voltage') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD min_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'max_phase_voltage') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD max_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'min_phase_voltage') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD min_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.yearly_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.yearly_measurements ADD reactive_energy_kvarh FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'line_voltage_avg') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD line_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'phase_voltage_avg') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD phase_voltage_avg FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'max_line_voltage') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD max_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'min_line_voltage') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD min_line_voltage FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'max_phase_voltage') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD max_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'min_phase_voltage') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD min_phase_voltage FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'power_factor') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD power_factor FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'max_power') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD max_power FLOAT NULL;

IF COL_LENGTH('dbo.hourly_measurements', 'reactive_energy_kvarh') IS NULL

    ALTER TABLE dbo.hourly_measurements ADD reactive_energy_kvarh FLOAT NULL;

GO



IF OBJECT_ID('dbo.hourly_measurements', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.hourly_measurements (

        hour_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,

        meter_id INT NULL,

        measured_hour DATETIME NOT NULL,

        avg_current FLOAT NULL,

        max_line_voltage FLOAT NULL,

        min_line_voltage FLOAT NULL,

        max_phase_voltage FLOAT NULL,

        min_phase_voltage FLOAT NULL,

        max_current FLOAT NULL,

        min_current FLOAT NULL,

        energy_consumed_kwh FLOAT NULL,

        line_voltage_avg FLOAT NULL,

        phase_voltage_avg FLOAT NULL,

        power_factor FLOAT NULL,

        max_power FLOAT NULL,

        reactive_energy_kvarh FLOAT NULL

    );

END;

GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.hourly_measurements') AND name = 'idx_hourly_meter_hour')

    CREATE UNIQUE NONCLUSTERED INDEX idx_hourly_meter_hour ON dbo.hourly_measurements (meter_id, measured_hour);

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.foreign_keys

    WHERE name = 'FK_hourly_measurements_meter'

      AND parent_object_id = OBJECT_ID('dbo.hourly_measurements')

)

BEGIN

    ALTER TABLE dbo.hourly_measurements WITH CHECK

        ADD CONSTRAINT FK_hourly_measurements_meter FOREIGN KEY (meter_id)

        REFERENCES dbo.meters(meter_id);

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_daily_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.daily_measurements AS t

    USING (

        SELECT

            m.meter_id,

            CAST(m.measured_at AS DATE) AS measured_date,

            AVG(m.average_current) AS avg_current,

            MAX(lv.row_max_line_voltage) AS max_line_voltage,

            MIN(lv.row_min_line_voltage) AS min_line_voltage,

            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,

            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,

            MAX(m.current_max) AS max_current,

            MIN(m.current_min) AS min_current,

            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,

            AVG(m.line_voltage_avg) AS line_voltage_avg,

            AVG(m.phase_voltage_avg) AS phase_voltage_avg,

            AVG(m.power_factor) AS power_factor,

            MAX(m.max_power) AS max_power,

            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements m

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_line_voltage,

                MIN(v) AS row_min_line_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),

                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),

                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)

            ) AS src(v)

        ) lv

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_phase_voltage,

                MIN(v) AS row_min_phase_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),

                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),

                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)

            ) AS src(v)

        ) pv

        WHERE m.measured_at >= DATEADD(DAY, -1, CAST(GETDATE() AS DATE))

        GROUP BY m.meter_id, CAST(m.measured_at AS DATE)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_date = s.measured_date)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_line_voltage = s.max_line_voltage,

            min_line_voltage = s.min_line_voltage,

            max_phase_voltage = s.max_phase_voltage,

            min_phase_voltage = s.min_phase_voltage,

            max_current = s.max_current,

            min_current = s.min_current,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_date,

            avg_current,

            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,

            max_current, min_current,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_date,

            s.avg_current,

            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,

            s.max_current, s.min_current,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_hourly_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.hourly_measurements AS t

    USING (

        SELECT

            m.meter_id,

            DATEADD(HOUR, DATEDIFF(HOUR, 0, m.measured_at), 0) AS measured_hour,

            AVG(m.average_current) AS avg_current,

            MAX(lv.row_max_line_voltage) AS max_line_voltage,

            MIN(lv.row_min_line_voltage) AS min_line_voltage,

            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,

            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,

            MAX(m.current_max) AS max_current,

            MIN(m.current_min) AS min_current,

            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,

            AVG(m.line_voltage_avg) AS line_voltage_avg,

            AVG(m.phase_voltage_avg) AS phase_voltage_avg,

            AVG(m.power_factor) AS power_factor,

            MAX(m.max_power) AS max_power,

            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements m

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_line_voltage,

                MIN(v) AS row_min_line_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),

                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),

                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)

            ) AS src(v)

        ) lv

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_phase_voltage,

                MIN(v) AS row_min_phase_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),

                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),

                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)

            ) AS src(v)

        ) pv

        WHERE m.measured_at >= DATEADD(DAY, -2, GETDATE())

        GROUP BY m.meter_id, DATEADD(HOUR, DATEDIFF(HOUR, 0, m.measured_at), 0)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_hour = s.measured_hour)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_line_voltage = s.max_line_voltage,

            min_line_voltage = s.min_line_voltage,

            max_phase_voltage = s.max_phase_voltage,

            min_phase_voltage = s.min_phase_voltage,

            max_current = s.max_current,

            min_current = s.min_current,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_hour,

            avg_current,

            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,

            max_current, min_current,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_hour,

            s.avg_current,

            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,

            s.max_current, s.min_current,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_monthly_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.monthly_measurements AS t

    USING (

        SELECT

            m.meter_id,

            DATEFROMPARTS(YEAR(m.measured_at), MONTH(m.measured_at), 1) AS measured_month,

            AVG(m.average_current) AS avg_current,

            MAX(lv.row_max_line_voltage) AS max_line_voltage,

            MIN(lv.row_min_line_voltage) AS min_line_voltage,

            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,

            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,

            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,

            AVG(m.line_voltage_avg) AS line_voltage_avg,

            AVG(m.phase_voltage_avg) AS phase_voltage_avg,

            AVG(m.power_factor) AS power_factor,

            MAX(m.max_power) AS max_power,

            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements m

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_line_voltage,

                MIN(v) AS row_min_line_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),

                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),

                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)

            ) AS src(v)

        ) lv

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_phase_voltage,

                MIN(v) AS row_min_phase_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),

                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),

                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)

            ) AS src(v)

        ) pv

        WHERE m.measured_at >= DATEADD(MONTH, -1, GETDATE())

        GROUP BY m.meter_id, YEAR(m.measured_at), MONTH(m.measured_at)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_month = s.measured_month)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_line_voltage = s.max_line_voltage,

            min_line_voltage = s.min_line_voltage,

            max_phase_voltage = s.max_phase_voltage,

            min_phase_voltage = s.min_phase_voltage,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_month,

            avg_current,

            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_month,

            s.avg_current,

            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_aggregate_yearly_measurements

AS

BEGIN

    SET NOCOUNT ON;



    MERGE dbo.yearly_measurements AS t

    USING (

        SELECT

            m.meter_id,

            YEAR(m.measured_at) AS measured_year,

            AVG(m.average_current) AS avg_current,

            MAX(lv.row_max_line_voltage) AS max_line_voltage,

            MIN(lv.row_min_line_voltage) AS min_line_voltage,

            MAX(pv.row_max_phase_voltage) AS max_phase_voltage,

            MIN(pv.row_min_phase_voltage) AS min_phase_voltage,

            MAX(m.energy_consumed_total) - MIN(m.energy_consumed_total) AS energy_consumed_kwh,

            AVG(m.line_voltage_avg) AS line_voltage_avg,

            AVG(m.phase_voltage_avg) AS phase_voltage_avg,

            AVG(m.power_factor) AS power_factor,

            MAX(m.max_power) AS max_power,

            MAX(m.reactive_energy_total) - MIN(m.reactive_energy_total) AS reactive_energy_kvarh

        FROM dbo.measurements m

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_line_voltage,

                MIN(v) AS row_min_line_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN NULL ELSE m.voltage_ab END),

                (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN NULL ELSE m.voltage_bc END),

                (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN NULL ELSE m.voltage_ca END)

            ) AS src(v)

        ) lv

        OUTER APPLY (

            SELECT

                MAX(v) AS row_max_phase_voltage,

                MIN(v) AS row_min_phase_voltage

            FROM (VALUES

                (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN NULL ELSE m.voltage_an END),

                (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN NULL ELSE m.voltage_bn END),

                (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN NULL ELSE m.voltage_cn END)

            ) AS src(v)

        ) pv

        WHERE m.measured_at >= DATEADD(YEAR, -1, GETDATE())

        GROUP BY m.meter_id, YEAR(m.measured_at)

    ) AS s

    ON (t.meter_id = s.meter_id AND t.measured_year = s.measured_year)

    WHEN MATCHED THEN

        UPDATE SET

            avg_current = s.avg_current,

            max_line_voltage = s.max_line_voltage,

            min_line_voltage = s.min_line_voltage,

            max_phase_voltage = s.max_phase_voltage,

            min_phase_voltage = s.min_phase_voltage,

            energy_consumed_kwh = s.energy_consumed_kwh,

            line_voltage_avg = s.line_voltage_avg,

            phase_voltage_avg = s.phase_voltage_avg,

            power_factor = s.power_factor,

            max_power = s.max_power,

            reactive_energy_kvarh = s.reactive_energy_kvarh

    WHEN NOT MATCHED THEN

        INSERT (

            meter_id, measured_year,

            avg_current,

            max_line_voltage, min_line_voltage, max_phase_voltage, min_phase_voltage,

            energy_consumed_kwh,

            line_voltage_avg, phase_voltage_avg, power_factor, max_power,

            reactive_energy_kvarh

        )

        VALUES (

            s.meter_id, s.measured_year,

            s.avg_current,

            s.max_line_voltage, s.min_line_voltage, s.max_phase_voltage, s.min_phase_voltage,

            s.energy_consumed_kwh,

            s.line_voltage_avg, s.phase_voltage_avg, s.power_factor, s.max_power,

            s.reactive_energy_kvarh

        );

END;

GO



CREATE OR ALTER VIEW dbo.vw_daily_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    d.day_id,

    d.measured_date,

    d.avg_current,

    d.max_line_voltage,

    d.min_line_voltage,

    d.max_phase_voltage,

    d.min_phase_voltage,

    d.max_current,

    d.min_current,

    d.energy_consumed_kwh,

    d.reactive_energy_kvarh,

    d.line_voltage_avg,

    d.phase_voltage_avg,

    d.power_factor,

    d.max_power

FROM dbo.daily_measurements d

INNER JOIN dbo.meters m ON m.meter_id = d.meter_id;

GO



CREATE OR ALTER VIEW dbo.vw_hourly_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    h.hour_id,

    h.measured_hour,

    h.avg_current,

    h.max_line_voltage,

    h.min_line_voltage,

    h.max_phase_voltage,

    h.min_phase_voltage,

    h.max_current,

    h.min_current,

    h.energy_consumed_kwh,

    h.reactive_energy_kvarh,

    h.line_voltage_avg,

    h.phase_voltage_avg,

    h.power_factor,

    h.max_power

FROM dbo.hourly_measurements h

INNER JOIN dbo.meters m ON m.meter_id = h.meter_id;

GO



CREATE OR ALTER VIEW dbo.vw_monthly_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    mm.month_id,

    mm.measured_month,

    mm.avg_current,

    mm.max_line_voltage,

    mm.min_line_voltage,

    mm.max_phase_voltage,

    mm.min_phase_voltage,

    mm.energy_consumed_kwh,

    mm.reactive_energy_kvarh,

    mm.line_voltage_avg,

    mm.phase_voltage_avg,

    mm.power_factor,

    mm.max_power

FROM dbo.monthly_measurements mm

INNER JOIN dbo.meters m ON m.meter_id = mm.meter_id;

GO



CREATE OR ALTER VIEW dbo.vw_yearly_measurements

AS

SELECT

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type,

    y.year_id,

    y.measured_year,

    y.avg_current,

    y.max_line_voltage,

    y.min_line_voltage,

    y.max_phase_voltage,

    y.min_phase_voltage,

    y.energy_consumed_kwh,

    y.reactive_energy_kvarh,

    y.line_voltage_avg,

    y.phase_voltage_avg,

    y.power_factor,

    y.max_power

FROM dbo.yearly_measurements y

INNER JOIN dbo.meters m ON m.meter_id = y.meter_id;

GO

/* ===== END update_aggregate_measurements_schema.sql ===== */



PRINT '--- 3. add_measurements_derived_columns_trigger.sql ---';

GO

/* ===== BEGIN add_measurements_derived_columns_trigger.sql ===== */

/*

   Auto-maintain derived min/max columns on dbo.measurements.



   Columns maintained

   - line_voltage_avg

   - phase_voltage_avg

   - average_current

   - voltage_max

   - voltage_min

   - current_max

   - current_min

   - power_factor_min

   - max_power

*/



USE EPMS;

GO



CREATE OR ALTER TRIGGER dbo.trg_measurements_derive_minmax

ON dbo.measurements

AFTER INSERT, UPDATE

AS

BEGIN

    SET NOCOUNT ON;



    UPDATE m

    SET

        line_voltage_avg = CASE

            WHEN i.line_voltage_avg IS NOT NULL AND ABS(i.line_voltage_avg) >= 0.001 THEN i.line_voltage_avg

            ELSE vv.line_voltage_avg_calc

        END,

        phase_voltage_avg = CASE

            WHEN i.phase_voltage_avg IS NOT NULL AND ABS(i.phase_voltage_avg) >= 0.001 THEN i.phase_voltage_avg

            ELSE vv.phase_voltage_avg_calc

        END,

        average_current = CASE

            WHEN i.average_current IS NOT NULL AND ABS(i.average_current) >= 0.001 THEN i.average_current

            ELSE cm.current_avg_calc

        END,

        voltage_max = vm.voltage_max_calc,

        voltage_min = vm.voltage_min_calc,

        current_max = cm.current_max_calc,

        current_min = cm.current_min_calc,

        power_factor_min = pf.power_factor_min_calc,

        max_power = CASE

            WHEN ps.peak_value IS NOT NULL THEN ps.peak_value

            WHEN i.max_power IS NOT NULL AND ABS(i.max_power) >= 0.001 THEN i.max_power

            ELSE pw.max_power_calc

        END

    FROM dbo.measurements m

    INNER JOIN inserted i

        ON i.measurement_id = m.measurement_id

    OUTER APPLY (

        SELECT

            AVG(line_v) AS line_voltage_avg_calc,

            AVG(phase_v) AS phase_voltage_avg_calc

        FROM (

            SELECT

                CASE WHEN ABS(COALESCE(m.voltage_ab, 0)) < 0.001 THEN NULL ELSE m.voltage_ab END AS line_v,

                CASE WHEN ABS(COALESCE(m.voltage_an, 0)) < 0.001 THEN NULL ELSE m.voltage_an END AS phase_v

            UNION ALL

            SELECT

                CASE WHEN ABS(COALESCE(m.voltage_bc, 0)) < 0.001 THEN NULL ELSE m.voltage_bc END,

                CASE WHEN ABS(COALESCE(m.voltage_bn, 0)) < 0.001 THEN NULL ELSE m.voltage_bn END

            UNION ALL

            SELECT

                CASE WHEN ABS(COALESCE(m.voltage_ca, 0)) < 0.001 THEN NULL ELSE m.voltage_ca END,

                CASE WHEN ABS(COALESCE(m.voltage_cn, 0)) < 0.001 THEN NULL ELSE m.voltage_cn END

        ) s

    ) vv

    OUTER APPLY (

        SELECT

            MAX(v) AS voltage_max_calc,

            MIN(v) AS voltage_min_calc

        FROM (VALUES

            (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN 0 ELSE m.voltage_ab END),

            (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN 0 ELSE m.voltage_bc END),

            (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN 0 ELSE m.voltage_ca END),

            (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN 0 ELSE m.voltage_an END),

            (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN 0 ELSE m.voltage_bn END),

            (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN 0 ELSE m.voltage_cn END),

            (CASE WHEN m.average_voltage IS NULL OR ABS(m.average_voltage) < 0.001 THEN 0 ELSE m.average_voltage END),

            (CASE WHEN m.line_voltage_avg IS NULL OR ABS(m.line_voltage_avg) < 0.001 THEN 0 ELSE m.line_voltage_avg END),

            (CASE WHEN m.phase_voltage_avg IS NULL OR ABS(m.phase_voltage_avg) < 0.001 THEN 0 ELSE m.phase_voltage_avg END)

        ) AS src(v)

        WHERE v IS NOT NULL

    ) vm

    OUTER APPLY (

        SELECT

            AVG(v) AS current_avg_calc,

            MAX(v) AS current_max_calc,

            MIN(v) AS current_min_calc

        FROM (VALUES

            (m.current_a),

            (m.current_b),

            (m.current_c),

            (m.current_n)

        ) AS src(v)

        WHERE v IS NOT NULL

    ) cm

    OUTER APPLY (

        SELECT

            MIN(v) AS power_factor_min_calc

        FROM (VALUES

            (m.power_factor_a),

            (m.power_factor_b),

            (m.power_factor_c),

            (m.power_factor),

            (m.power_factor_avg)

        ) AS src(v)

        WHERE v IS NOT NULL

    ) pf

    OUTER APPLY (

        SELECT

            MAX(v) AS max_power_calc

        FROM (VALUES

            (CASE WHEN m.active_power_total IS NULL THEN NULL ELSE ABS(m.active_power_total) END),

            (CASE WHEN m.active_power_a IS NULL THEN NULL ELSE ABS(m.active_power_a) END),

            (CASE WHEN m.active_power_b IS NULL THEN NULL ELSE ABS(m.active_power_b) END),

            (CASE WHEN m.active_power_c IS NULL THEN NULL ELSE ABS(m.active_power_c) END)

        ) AS src(v)

        WHERE v IS NOT NULL

    ) pw

    OUTER APPLY (

        SELECT TOP 1 s.value_float AS peak_value

        FROM dbo.plc_ai_mapping_master am

        INNER JOIN dbo.plc_ai_samples s

            ON s.meter_id = m.meter_id

           AND s.reg_address = am.reg_address

        WHERE am.enabled = 1

          AND am.meter_id = m.meter_id

          AND (am.measurement_column = 'max_power' OR am.token = 'PEAK')

          AND s.measured_at BETWEEN DATEADD(SECOND, -2, m.measured_at) AND DATEADD(SECOND, 2, m.measured_at)

        ORDER BY ABS(DATEDIFF(SECOND, s.measured_at, m.measured_at)), ABS(DATEDIFF(MINUTE, s.measured_at, m.measured_at))

    ) ps;

END;

GO



UPDATE m

SET

    line_voltage_avg = CASE

        WHEN m.line_voltage_avg IS NOT NULL AND ABS(m.line_voltage_avg) >= 0.001 THEN m.line_voltage_avg

        ELSE vv.line_voltage_avg_calc

    END,

    phase_voltage_avg = CASE

        WHEN m.phase_voltage_avg IS NOT NULL AND ABS(m.phase_voltage_avg) >= 0.001 THEN m.phase_voltage_avg

        ELSE vv.phase_voltage_avg_calc

    END,

    average_current = CASE

        WHEN m.average_current IS NOT NULL AND ABS(m.average_current) >= 0.001 THEN m.average_current

        ELSE cm.current_avg_calc

    END,

    voltage_max = vm.voltage_max_calc,

    voltage_min = vm.voltage_min_calc,

    current_max = cm.current_max_calc,

    current_min = cm.current_min_calc,

    power_factor_min = pf.power_factor_min_calc,

    max_power = COALESCE(ps.peak_value, pw.max_power_calc)

FROM dbo.measurements m

OUTER APPLY (

    SELECT

        AVG(line_v) AS line_voltage_avg_calc,

        AVG(phase_v) AS phase_voltage_avg_calc

    FROM (

        SELECT

            CASE WHEN ABS(COALESCE(m.voltage_ab, 0)) < 0.001 THEN NULL ELSE m.voltage_ab END AS line_v,

            CASE WHEN ABS(COALESCE(m.voltage_an, 0)) < 0.001 THEN NULL ELSE m.voltage_an END AS phase_v

        UNION ALL

        SELECT

            CASE WHEN ABS(COALESCE(m.voltage_bc, 0)) < 0.001 THEN NULL ELSE m.voltage_bc END,

            CASE WHEN ABS(COALESCE(m.voltage_bn, 0)) < 0.001 THEN NULL ELSE m.voltage_bn END

        UNION ALL

        SELECT

            CASE WHEN ABS(COALESCE(m.voltage_ca, 0)) < 0.001 THEN NULL ELSE m.voltage_ca END,

            CASE WHEN ABS(COALESCE(m.voltage_cn, 0)) < 0.001 THEN NULL ELSE m.voltage_cn END

    ) s

) vv

OUTER APPLY (

    SELECT

        MAX(v) AS voltage_max_calc,

        MIN(v) AS voltage_min_calc

    FROM (VALUES

        (CASE WHEN m.voltage_ab IS NULL OR ABS(m.voltage_ab) < 0.001 THEN 0 ELSE m.voltage_ab END),

        (CASE WHEN m.voltage_bc IS NULL OR ABS(m.voltage_bc) < 0.001 THEN 0 ELSE m.voltage_bc END),

        (CASE WHEN m.voltage_ca IS NULL OR ABS(m.voltage_ca) < 0.001 THEN 0 ELSE m.voltage_ca END),

        (CASE WHEN m.voltage_an IS NULL OR ABS(m.voltage_an) < 0.001 THEN 0 ELSE m.voltage_an END),

        (CASE WHEN m.voltage_bn IS NULL OR ABS(m.voltage_bn) < 0.001 THEN 0 ELSE m.voltage_bn END),

        (CASE WHEN m.voltage_cn IS NULL OR ABS(m.voltage_cn) < 0.001 THEN 0 ELSE m.voltage_cn END),

        (CASE WHEN m.average_voltage IS NULL OR ABS(m.average_voltage) < 0.001 THEN 0 ELSE m.average_voltage END),

        (CASE WHEN m.line_voltage_avg IS NULL OR ABS(m.line_voltage_avg) < 0.001 THEN 0 ELSE m.line_voltage_avg END),

        (CASE WHEN m.phase_voltage_avg IS NULL OR ABS(m.phase_voltage_avg) < 0.001 THEN 0 ELSE m.phase_voltage_avg END)

    ) AS src(v)

    WHERE v IS NOT NULL

) vm

OUTER APPLY (

    SELECT

        AVG(v) AS current_avg_calc,

        MAX(v) AS current_max_calc,

        MIN(v) AS current_min_calc

    FROM (VALUES

        (m.current_a),

        (m.current_b),

        (m.current_c),

        (m.current_n)

    ) AS src(v)

    WHERE v IS NOT NULL

) cm

OUTER APPLY (

    SELECT

        MIN(v) AS power_factor_min_calc

    FROM (VALUES

        (m.power_factor_a),

        (m.power_factor_b),

        (m.power_factor_c),

        (m.power_factor),

        (m.power_factor_avg)

    ) AS src(v)

    WHERE v IS NOT NULL

) pf

OUTER APPLY (

    SELECT

        MAX(v) AS max_power_calc

    FROM (VALUES

        (CASE WHEN m.active_power_total IS NULL THEN NULL ELSE ABS(m.active_power_total) END),

        (CASE WHEN m.active_power_a IS NULL THEN NULL ELSE ABS(m.active_power_a) END),

        (CASE WHEN m.active_power_b IS NULL THEN NULL ELSE ABS(m.active_power_b) END),

        (CASE WHEN m.active_power_c IS NULL THEN NULL ELSE ABS(m.active_power_c) END)

    ) AS src(v)

    WHERE v IS NOT NULL

) pw

OUTER APPLY (

    SELECT TOP 1 s.value_float AS peak_value

    FROM dbo.plc_ai_mapping_master am

    INNER JOIN dbo.plc_ai_samples s

        ON s.meter_id = m.meter_id

       AND s.reg_address = am.reg_address

    WHERE am.enabled = 1

      AND am.meter_id = m.meter_id

      AND (am.measurement_column = 'max_power' OR am.token = 'PEAK')

      AND s.measured_at BETWEEN DATEADD(SECOND, -2, m.measured_at) AND DATEADD(SECOND, 2, m.measured_at)

    ORDER BY ABS(DATEDIFF(SECOND, s.measured_at, m.measured_at)), ABS(DATEDIFF(MINUTE, s.measured_at, m.measured_at))

) ps

;

GO

/* ===== END add_measurements_derived_columns_trigger.sql ===== */



PRINT '--- 4. add_alarm_log_rule_columns.sql ---';

GO

/* ===== BEGIN add_alarm_log_rule_columns.sql ===== */

IF COL_LENGTH('dbo.alarm_log','rule_id') IS NULL

    ALTER TABLE dbo.alarm_log ADD rule_id INT NULL;

GO



IF COL_LENGTH('dbo.alarm_log','rule_code') IS NULL

    ALTER TABLE dbo.alarm_log ADD rule_code VARCHAR(50) NULL;

GO



IF COL_LENGTH('dbo.alarm_log','metric_key') IS NULL

    ALTER TABLE dbo.alarm_log ADD metric_key VARCHAR(100) NULL;

GO



IF COL_LENGTH('dbo.alarm_log','source_token') IS NULL

    ALTER TABLE dbo.alarm_log ADD source_token VARCHAR(120) NULL;

GO

/* ===== END add_alarm_log_rule_columns.sql ===== */



PRINT '--- 5. create_plc_mapping_master.sql ---';

GO

/* ===== BEGIN create_plc_mapping_master.sql ===== */

SET NOCOUNT ON;

SET ANSI_NULLS ON;

SET QUOTED_IDENTIFIER ON;



IF OBJECT_ID('dbo.plc_ai_mapping_master', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.plc_ai_mapping_master (

        plc_id INT NOT NULL,

        meter_id INT NOT NULL,

        float_index INT NOT NULL,

        token NVARCHAR(100) NOT NULL,

        reg_address INT NOT NULL,

        byte_order NVARCHAR(10) NOT NULL CONSTRAINT DF_plc_ai_mapping_master_byte_order DEFAULT ('ABCD'),

        measurement_column NVARCHAR(128) NULL,

        target_table NVARCHAR(64) NOT NULL CONSTRAINT DF_plc_ai_mapping_master_target_table DEFAULT ('measurements'),

        db_insert_yn BIT NOT NULL CONSTRAINT DF_plc_ai_mapping_master_db_insert DEFAULT ((1)),

        enabled BIT NOT NULL CONSTRAINT DF_plc_ai_mapping_master_enabled DEFAULT ((1)),

        note NVARCHAR(400) NULL,

        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_plc_ai_mapping_master_updated DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_plc_ai_mapping_master PRIMARY KEY (plc_id, meter_id, float_index)

    );

END;

GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_ai_mapping_master') AND name = 'IX_plc_ai_mapping_master_token_idx')

    CREATE INDEX IX_plc_ai_mapping_master_token_idx ON dbo.plc_ai_mapping_master (token, float_index);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_ai_mapping_master') AND name = 'IX_plc_ai_mapping_master_meter_addr')

    CREATE INDEX IX_plc_ai_mapping_master_meter_addr ON dbo.plc_ai_mapping_master (plc_id, meter_id, reg_address);

GO



IF OBJECT_ID('dbo.plc_di_mapping_master', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.plc_di_mapping_master (

        plc_id INT NOT NULL,

        point_id INT NOT NULL,

        di_address INT NOT NULL,

        bit_no INT NOT NULL,

        meter_id INT NULL,

        tag_name NVARCHAR(255) NULL,

        item_name NVARCHAR(255) NULL,

        panel_name NVARCHAR(255) NULL,

        enabled BIT NOT NULL CONSTRAINT DF_plc_di_mapping_master_enabled DEFAULT ((1)),

        note NVARCHAR(400) NULL,

        updated_at DATETIME2(7) NOT NULL CONSTRAINT DF_plc_di_mapping_master_updated DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_plc_di_mapping_master PRIMARY KEY (plc_id, point_id, di_address, bit_no)

    );

END;

GO



IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_addr')

    CREATE INDEX IX_plc_di_mapping_master_addr ON dbo.plc_di_mapping_master (plc_id, di_address, bit_no);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_panel')

    CREATE INDEX IX_plc_di_mapping_master_panel ON dbo.plc_di_mapping_master (panel_name, item_name);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_meter')

    CREATE INDEX IX_plc_di_mapping_master_meter ON dbo.plc_di_mapping_master (meter_id, plc_id, point_id, di_address, bit_no);

GO



;WITH ai_src AS (

    SELECT

        pm.plc_id,

        pm.meter_id,

        ROW_NUMBER() OVER (PARTITION BY pm.plc_id, pm.meter_id ORDER BY (SELECT 1)) AS float_index,

        UPPER(LTRIM(RTRIM(CASE WHEN x.i.value('.', 'nvarchar(100)') = 'KHH' THEN 'KWH' ELSE x.i.value('.', 'nvarchar(100)') END))) AS token,

        pm.start_address + ((ROW_NUMBER() OVER (PARTITION BY pm.plc_id, pm.meter_id ORDER BY (SELECT 1)) - 1) * 2) AS reg_address,

        COALESCE(NULLIF(pm.byte_order, ''), 'ABCD') AS byte_order

    FROM dbo.plc_meter_map pm

    CROSS APPLY (

        SELECT TRY_CAST('<r><i>' +

                        REPLACE(REPLACE(REPLACE(ISNULL(pm.metric_order, ''), '&', '&amp;'), '<', '&lt;'), ',', '</i><i>') +

                        '</i></r>' AS XML) AS metric_xml

    ) q

    CROSS APPLY q.metric_xml.nodes('/r/i') x(i)

    WHERE pm.enabled = 1

      AND ISNULL(pm.metric_order, '') <> ''

),

ai_meta AS (

    SELECT

        UPPER(LTRIM(RTRIM(token))) AS token,

        float_index,

        measurement_column,

        target_table,

        is_supported,

        note

    FROM dbo.plc_ai_measurements_match

),

ai_seed AS (

    SELECT

        s.plc_id,

        s.meter_id,

        s.float_index,

        s.token,

        s.reg_address,

        s.byte_order,

        CASE

            WHEN s.token = 'IR' THEN NULL

            WHEN s.token = 'VA' AND s.float_index = 8 THEN 'phase_voltage_avg'

            WHEN s.token = 'VA' AND s.float_index = 18 THEN 'apparent_power_total'

            WHEN s.token = 'VAH' AND s.float_index = 19 THEN 'apparent_energy_total'

            WHEN s.token = 'KWH' AND s.float_index = 17 THEN 'energy_consumed_total'

            WHEN s.token = 'PST' AND s.float_index = 63 THEN 'flicker_pst'

            WHEN s.token = 'PLT' AND s.float_index = 64 THEN 'flicker_plt'

            ELSE m.measurement_column

        END AS measurement_column,

        CASE

            WHEN s.token IN ('PST', 'PLT') THEN 'flicker_measurements'

            WHEN s.token = 'IR' THEN 'measurements'

            ELSE COALESCE(NULLIF(m.target_table, ''), 'measurements')

        END AS target_table,

        CASE

            WHEN s.token = 'IR' THEN CAST(0 AS BIT)

            WHEN m.is_supported IS NULL THEN CAST(0 AS BIT)

            ELSE CAST(m.is_supported AS BIT)

        END AS db_insert_yn,

        CAST(1 AS BIT) AS enabled,

        CASE

            WHEN s.token = 'IR' THEN N'DB 미적재 PLC 전용'

            WHEN s.token = 'VA' AND s.float_index = 8 THEN N'상전압평균'

            WHEN s.token = 'VA' AND s.float_index = 18 THEN N'피상전력'

            WHEN s.token = 'VAH' AND s.float_index = 19 THEN N'피상전력량'

            ELSE m.note

        END AS note

    FROM ai_src s

    LEFT JOIN ai_meta m

      ON m.token = s.token

     AND (m.float_index = s.float_index OR m.float_index IS NULL)

)

MERGE dbo.plc_ai_mapping_master AS t

USING ai_seed AS s

ON (t.plc_id = s.plc_id AND t.meter_id = s.meter_id AND t.float_index = s.float_index)

WHEN MATCHED THEN

    UPDATE SET

        token = s.token,

        reg_address = s.reg_address,

        byte_order = s.byte_order,

        measurement_column = s.measurement_column,

        target_table = s.target_table,

        db_insert_yn = s.db_insert_yn,

        enabled = s.enabled,

        note = s.note,

        updated_at = SYSUTCDATETIME()

WHEN NOT MATCHED THEN

    INSERT (plc_id, meter_id, float_index, token, reg_address, byte_order, measurement_column, target_table, db_insert_yn, enabled, note, updated_at)

    VALUES (s.plc_id, s.meter_id, s.float_index, s.token, s.reg_address, s.byte_order, s.measurement_column, s.target_table, s.db_insert_yn, s.enabled, s.note, SYSUTCDATETIME());

GO



;WITH di_seed AS (

    SELECT

        dt.plc_id,

        dt.point_id,

        dt.di_address,

        dt.bit_no,

        COALESCE(mp_exact.meter_id, mp_name.meter_id, mp_panel.meter_id) AS meter_id,

        dt.tag_name,

        dt.item_name,

        dt.panel_name,

        CAST(CASE WHEN ISNULL(dm.enabled, 1) = 1 AND ISNULL(dt.enabled, 1) = 1 THEN 1 ELSE 0 END AS BIT) AS enabled,

        CAST(NULL AS NVARCHAR(400)) AS note

    FROM dbo.plc_di_tag_map dt

    LEFT JOIN dbo.plc_di_map dm

      ON dm.plc_id = dt.plc_id

     AND dm.point_id = dt.point_id

    OUTER APPLY (

        SELECT TOP 1 m.meter_id

        FROM dbo.meters m

        WHERE dt.item_name IS NOT NULL

          AND dt.panel_name IS NOT NULL

          AND UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(dt.item_name)))

          AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(dt.panel_name)))

        ORDER BY m.meter_id

    ) mp_exact

    OUTER APPLY (

        SELECT TOP 1 m.meter_id

        FROM dbo.meters m

        WHERE mp_exact.meter_id IS NULL

          AND dt.item_name IS NOT NULL

          AND UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(dt.item_name)))

        ORDER BY m.meter_id

    ) mp_name

    OUTER APPLY (

        SELECT CASE WHEN COUNT(*) = 1 THEN MIN(m.meter_id) END AS meter_id

        FROM dbo.meters m

        WHERE mp_exact.meter_id IS NULL

          AND mp_name.meter_id IS NULL

          AND dt.panel_name IS NOT NULL

          AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(dt.panel_name)))

    ) mp_panel

)

MERGE dbo.plc_di_mapping_master AS t

USING di_seed AS s

ON (t.plc_id = s.plc_id AND t.point_id = s.point_id AND t.di_address = s.di_address AND t.bit_no = s.bit_no)

WHEN MATCHED THEN

    UPDATE SET

        meter_id = s.meter_id,

        tag_name = s.tag_name,

        item_name = s.item_name,

        panel_name = s.panel_name,

        enabled = s.enabled,

        note = s.note,

        updated_at = SYSUTCDATETIME()

WHEN NOT MATCHED THEN

    INSERT (plc_id, point_id, di_address, bit_no, meter_id, tag_name, item_name, panel_name, enabled, note, updated_at)

    VALUES (s.plc_id, s.point_id, s.di_address, s.bit_no, s.meter_id, s.tag_name, s.item_name, s.panel_name, s.enabled, s.note, SYSUTCDATETIME());

/* ===== END create_plc_mapping_master.sql ===== */



PRINT '--- 6. migrate_to_meter_centric_di.sql ---';

GO

/* ===== BEGIN migrate_to_meter_centric_di.sql ===== */

SET NOCOUNT ON;

SET XACT_ABORT ON;



-- Follow with docs/sql/src/seed_di_virtual_meters.sql to create DI-only

-- representative meters for any logical DI groups that still cannot map

-- to an existing physical power meter after this first-pass migration.



BEGIN TRY

    BEGIN TRANSACTION;



    IF COL_LENGTH('dbo.plc_di_mapping_master', 'meter_id') IS NULL

        ALTER TABLE dbo.plc_di_mapping_master ADD meter_id INT NULL;



    EXEC('

        ;WITH meter_seed AS (

            SELECT

                d.plc_id,

                d.point_id,

                d.di_address,

                d.bit_no,

                COALESCE(mp_exact.meter_id, mp_name.meter_id, mp_panel.meter_id) AS meter_id

            FROM dbo.plc_di_mapping_master d

            OUTER APPLY (

                SELECT TOP 1 m.meter_id

                FROM dbo.meters m

                WHERE d.item_name IS NOT NULL

                  AND d.panel_name IS NOT NULL

                  AND UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(d.item_name)))

                  AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(d.panel_name)))

                ORDER BY m.meter_id

            ) mp_exact

            OUTER APPLY (

                SELECT TOP 1 m.meter_id

                FROM dbo.meters m

                WHERE mp_exact.meter_id IS NULL

                  AND d.item_name IS NOT NULL

                  AND UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(d.item_name)))

                ORDER BY m.meter_id

            ) mp_name

            OUTER APPLY (

                SELECT CASE WHEN COUNT(*) = 1 THEN MIN(m.meter_id) END AS meter_id

                FROM dbo.meters m

                WHERE mp_exact.meter_id IS NULL

                  AND mp_name.meter_id IS NULL

                  AND d.panel_name IS NOT NULL

                  AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(d.panel_name)))

            ) mp_panel

        )

        UPDATE d

        SET meter_id = s.meter_id

        FROM dbo.plc_di_mapping_master d

        JOIN meter_seed s

          ON s.plc_id = d.plc_id

         AND s.point_id = d.point_id

         AND s.di_address = d.di_address

         AND s.bit_no = d.bit_no

        WHERE d.meter_id IS NULL

          AND s.meter_id IS NOT NULL;

    ');



    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.plc_di_mapping_master') AND name = 'IX_plc_di_mapping_master_meter')

        CREATE INDEX IX_plc_di_mapping_master_meter ON dbo.plc_di_mapping_master (meter_id, plc_id, point_id, di_address, bit_no);



    IF NOT EXISTS (

        SELECT 1 FROM sys.foreign_keys

        WHERE parent_object_id = OBJECT_ID('dbo.plc_di_mapping_master')

          AND name = 'FK_plc_di_mapping_master_meter'

    )

        ALTER TABLE dbo.plc_di_mapping_master WITH NOCHECK

        ADD CONSTRAINT FK_plc_di_mapping_master_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id);



    IF COL_LENGTH('dbo.device_events', 'meter_id') IS NULL

        ALTER TABLE dbo.device_events ADD meter_id INT NULL;



    EXEC('

        UPDATE dbo.device_events

        SET meter_id = device_id

        WHERE meter_id IS NULL

          AND device_id IS NOT NULL;

    ');



    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.device_events') AND name = 'idx_device_event_meter_time')

        CREATE INDEX idx_device_event_meter_time ON dbo.device_events (meter_id, event_time DESC);



    IF NOT EXISTS (

        SELECT 1 FROM sys.foreign_keys

        WHERE parent_object_id = OBJECT_ID('dbo.device_events')

          AND name = 'FK_device_events_meter_id'

    )

        ALTER TABLE dbo.device_events WITH NOCHECK

        ADD CONSTRAINT FK_device_events_meter_id FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id);



    IF OBJECT_ID(N'[dbo].[vw_device_event_log]', N'V') IS NOT NULL

        DROP VIEW [dbo].[vw_device_event_log];



    EXEC('

        CREATE VIEW dbo.vw_device_event_log AS

        SELECT

            COALESCE(e.meter_id, e.device_id) AS meter_id,

            m.name AS meter_name,

            m.panel_name,

            m.building_name,

            m.usage_type,

            e.event_id,

            e.event_type,

            e.event_time,

            e.restored_time,

            e.severity,

            e.description,

            e.trip_count,

            e.outage_count,

            e.switch_count,

            e.downtime_minutes,

            e.duration_seconds,

            e.operating_time_minutes

        FROM dbo.device_events e

        LEFT JOIN dbo.meters m

          ON m.meter_id = COALESCE(e.meter_id, e.device_id);

    ');



    COMMIT TRANSACTION;

END TRY

BEGIN CATCH

    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    THROW;

END CATCH;



EXEC('

    SELECT

        (SELECT COUNT(*) FROM dbo.plc_di_mapping_master WHERE meter_id IS NOT NULL) AS di_mapping_with_meter_id,

        (SELECT COUNT(*) FROM dbo.plc_di_mapping_master WHERE meter_id IS NULL) AS di_mapping_without_meter_id,

        (SELECT COUNT(*) FROM dbo.device_events WHERE meter_id IS NOT NULL) AS device_events_with_meter_id,

        (SELECT COUNT(*) FROM dbo.device_events WHERE meter_id IS NULL) AS device_events_without_meter_id;

');

/* ===== END migrate_to_meter_centric_di.sql ===== */



PRINT '--- 7. seed_di_virtual_meters.sql ---';

GO

/* ===== BEGIN seed_di_virtual_meters.sql ===== */

SET NOCOUNT ON;

SET XACT_ABORT ON;



BEGIN TRY

    BEGIN TRANSACTION;



    DECLARE @base_meter_id INT = ISNULL((SELECT MAX(meter_id) FROM dbo.meters), 0);



    SET IDENTITY_INSERT dbo.meters ON;



    ;WITH unresolved_groups AS (

        SELECT DISTINCT

            LTRIM(RTRIM(d.item_name)) AS item_name,

            LTRIM(RTRIM(d.panel_name)) AS panel_name

        FROM dbo.plc_di_mapping_master d

        WHERE d.meter_id IS NULL

          AND ISNULL(LTRIM(RTRIM(d.item_name)), '') <> ''

          AND ISNULL(LTRIM(RTRIM(d.panel_name)), '') <> ''

    ),

    missing_groups AS (

        SELECT g.item_name, g.panel_name

        FROM unresolved_groups g

        WHERE NOT EXISTS (

            SELECT 1

            FROM dbo.meters m

            WHERE UPPER(LTRIM(RTRIM(m.name))) = UPPER(g.item_name)

              AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(g.panel_name)

        )

    ),

    seed_rows AS (

        SELECT

            ROW_NUMBER() OVER (ORDER BY g.panel_name, g.item_name) AS rn,

            g.item_name,

            g.panel_name,

            COALESCE(panel_meta.building_name, default_meta.building_name) AS building_name,

            CAST('DI' AS VARCHAR(50)) AS usage_type,

            panel_meta.rated_voltage,

            panel_meta.rated_current

        FROM missing_groups g

        OUTER APPLY (

            SELECT TOP 1

                m.building_name,

                m.rated_voltage,

                m.rated_current

            FROM dbo.meters m

            WHERE UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(g.panel_name)

            ORDER BY

                CASE WHEN m.rated_voltage IS NULL THEN 1 ELSE 0 END,

                CASE WHEN m.rated_current IS NULL THEN 1 ELSE 0 END,

                m.meter_id

        ) panel_meta

        OUTER APPLY (

            SELECT TOP 1

                m.building_name

            FROM dbo.meters m

            WHERE ISNULL(LTRIM(RTRIM(m.building_name)), '') <> ''

            GROUP BY m.building_name

            ORDER BY COUNT(*) DESC, m.building_name

        ) default_meta

    )

    INSERT INTO dbo.meters (

        meter_id,

        name,

        panel_name,

        building_name,

        usage_type,

        rated_voltage,

        rated_current

    )

    SELECT

        @base_meter_id + s.rn,

        s.item_name,

        s.panel_name,

        s.building_name,

        s.usage_type,

        s.rated_voltage,

        s.rated_current

    FROM seed_rows s;



    UPDATE d

    SET d.meter_id = m.meter_id

    FROM dbo.plc_di_mapping_master d

    JOIN dbo.meters m

      ON UPPER(LTRIM(RTRIM(m.name))) = UPPER(LTRIM(RTRIM(d.item_name)))

     AND UPPER(LTRIM(RTRIM(m.panel_name))) = UPPER(LTRIM(RTRIM(d.panel_name)))

    WHERE d.meter_id IS NULL;



    SET IDENTITY_INSERT dbo.meters OFF;



    COMMIT TRANSACTION;

END TRY

BEGIN CATCH

    IF (OBJECT_ID('dbo.meters', 'U') IS NOT NULL)

    BEGIN

        BEGIN TRY

            SET IDENTITY_INSERT dbo.meters OFF;

        END TRY

        BEGIN CATCH

        END CATCH;

    END



    IF @@TRANCOUNT > 0

        ROLLBACK TRANSACTION;

    THROW;

END CATCH;



SELECT COUNT(*) AS di_virtual_meter_count

FROM dbo.meters

WHERE usage_type = 'DI';



SELECT COUNT(*) AS di_mapping_without_meter_id

FROM dbo.plc_di_mapping_master

WHERE meter_id IS NULL;



SELECT meter_id, name, panel_name, building_name, usage_type

FROM dbo.meters

WHERE usage_type = 'DI'

ORDER BY meter_id;

/* ===== END seed_di_virtual_meters.sql ===== */



PRINT '--- 8. add_plc_ai_samples_trigger_lookup_index.sql ---';

GO

/* ===== BEGIN add_plc_ai_samples_trigger_lookup_index.sql ===== */

USE epms;

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'dbo.plc_ai_samples')

      AND name = N'IX_plc_ai_samples_meter_reg_measured_at'

)

BEGIN

    CREATE NONCLUSTERED INDEX IX_plc_ai_samples_meter_reg_measured_at

    ON dbo.plc_ai_samples (meter_id, reg_address, measured_at DESC)

    INCLUDE (value_float);

END

GO

/* ===== END add_plc_ai_samples_trigger_lookup_index.sql ===== */



PRINT '--- 9. add_verify_page_indexes.sql ---';

GO

/* ===== BEGIN add_verify_page_indexes.sql ===== */

IF NOT EXISTS (

    SELECT 1 FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'dbo.plc_ai_samples')

      AND name = N'IX_plc_ai_samples_plc_meter_measured_reg'

)

BEGIN

    CREATE NONCLUSTERED INDEX IX_plc_ai_samples_plc_meter_measured_reg

    ON dbo.plc_ai_samples (plc_id, meter_id, measured_at DESC, reg_address)

    INCLUDE (value_float, byte_order, quality);

END;



IF NOT EXISTS (

    SELECT 1 FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'dbo.plc_ai_samples')

      AND name = N'IX_plc_ai_samples_meter_reg_measured_at'

)

BEGIN

    CREATE NONCLUSTERED INDEX IX_plc_ai_samples_meter_reg_measured_at

    ON dbo.plc_ai_samples (meter_id, reg_address, measured_at DESC)

    INCLUDE (value_float);

END;



IF NOT EXISTS (

    SELECT 1 FROM sys.indexes

    WHERE object_id = OBJECT_ID(N'dbo.harmonic_measurements')

      AND name = N'IX_harmonic_measurements_meter_time'

)

BEGIN

    CREATE NONCLUSTERED INDEX IX_harmonic_measurements_meter_time

    ON dbo.harmonic_measurements (meter_id, measured_at DESC);

END;

/* ===== END add_verify_page_indexes.sql ===== */



PRINT '--- 10. create_epms_tenant_billing_schema.sql ---';

GO

/* ===== BEGIN create_epms_tenant_billing_schema.sql ===== */

SET ANSI_NULLS ON;

SET QUOTED_IDENTIFIER ON;

GO



USE [epms];

GO



/*==============================================================

  EPMS Tenant Billing Subschema

  Purpose:

    - Department-store tenant electricity settlement

    - Keep metering tables as-is and add billing-side tables

==============================================================*/



IF OBJECT_ID(N'dbo.tenant_store', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.tenant_store (

        store_id int IDENTITY(1,1) NOT NULL,

        store_code varchar(50) NOT NULL,

        store_name nvarchar(150) NOT NULL,

        business_number varchar(30) NULL,

        building_name varchar(100) NULL,

        floor_name varchar(50) NULL,

        room_name varchar(50) NULL,

        zone_name varchar(100) NULL,

        category_name varchar(100) NULL,

        contact_name nvarchar(80) NULL,

        contact_phone varchar(50) NULL,

        status varchar(20) NOT NULL CONSTRAINT DF_tenant_store_status DEFAULT ('ACTIVE'),

        opened_on date NULL,

        closed_on date NULL,

        notes nvarchar(500) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_store_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_store_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_tenant_store PRIMARY KEY CLUSTERED (store_id ASC),

        CONSTRAINT UX_tenant_store_code UNIQUE NONCLUSTERED (store_code ASC)

    );



    CREATE INDEX IX_tenant_store_building_status ON dbo.tenant_store(building_name ASC, status ASC);

END

GO



IF OBJECT_ID(N'dbo.tenant_meter_map', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.tenant_meter_map (

        map_id bigint IDENTITY(1,1) NOT NULL,

        store_id int NOT NULL,

        meter_id int NOT NULL,

        billing_scope varchar(20) NOT NULL CONSTRAINT DF_tenant_meter_map_scope DEFAULT ('DIRECT'),

        allocation_ratio decimal(9,6) NOT NULL CONSTRAINT DF_tenant_meter_map_ratio DEFAULT ((1.000000)),

        is_primary bit NOT NULL CONSTRAINT DF_tenant_meter_map_primary DEFAULT ((0)),

        valid_from date NOT NULL,

        valid_to date NULL,

        notes nvarchar(300) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_meter_map_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_meter_map_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_tenant_meter_map PRIMARY KEY CLUSTERED (map_id ASC),

        CONSTRAINT FK_tenant_meter_map_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),

        CONSTRAINT FK_tenant_meter_map_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id),

        CONSTRAINT CK_tenant_meter_map_ratio CHECK (allocation_ratio > 0 AND allocation_ratio <= 1.000000),

        CONSTRAINT CK_tenant_meter_map_valid_range CHECK (valid_to IS NULL OR valid_to >= valid_from)

    );



    CREATE INDEX IX_tenant_meter_map_store_dates ON dbo.tenant_meter_map(store_id ASC, valid_from ASC, valid_to ASC);

    CREATE INDEX IX_tenant_meter_map_meter_dates ON dbo.tenant_meter_map(meter_id ASC, valid_from ASC, valid_to ASC);

END

GO



IF OBJECT_ID(N'dbo.billing_cycle', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.billing_cycle (

        cycle_id int IDENTITY(1,1) NOT NULL,

        cycle_code varchar(20) NOT NULL,

        period_type varchar(20) NOT NULL CONSTRAINT DF_billing_cycle_period_type DEFAULT ('MONTHLY'),

        cycle_start_date date NOT NULL,

        cycle_end_date date NOT NULL,

        reading_closed_at datetime2(0) NULL,

        status varchar(20) NOT NULL CONSTRAINT DF_billing_cycle_status DEFAULT ('DRAFT'),

        notes nvarchar(300) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_cycle_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_cycle_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_billing_cycle PRIMARY KEY CLUSTERED (cycle_id ASC),

        CONSTRAINT UX_billing_cycle_code UNIQUE NONCLUSTERED (cycle_code ASC),

        CONSTRAINT CK_billing_cycle_range CHECK (cycle_end_date >= cycle_start_date)

    );



    CREATE INDEX IX_billing_cycle_dates ON dbo.billing_cycle(cycle_start_date ASC, cycle_end_date ASC, status ASC);

END

GO



IF OBJECT_ID(N'dbo.billing_rate', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.billing_rate (

        rate_id int IDENTITY(1,1) NOT NULL,

        rate_code varchar(50) NOT NULL,

        rate_name nvarchar(150) NOT NULL,

        effective_from date NOT NULL,

        effective_to date NULL,

        currency_code varchar(10) NOT NULL CONSTRAINT DF_billing_rate_currency DEFAULT ('KRW'),

        unit_price_per_kwh decimal(18,4) NOT NULL CONSTRAINT DF_billing_rate_unit_price DEFAULT ((0)),

        basic_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_rate_basic DEFAULT ((0)),

        demand_unit_price decimal(18,4) NOT NULL CONSTRAINT DF_billing_rate_demand DEFAULT ((0)),

        vat_rate decimal(9,6) NOT NULL CONSTRAINT DF_billing_rate_vat DEFAULT ((0.100000)),

        fund_rate decimal(9,6) NOT NULL CONSTRAINT DF_billing_rate_fund DEFAULT ((0.037000)),

        is_active bit NOT NULL CONSTRAINT DF_billing_rate_active DEFAULT ((1)),

        notes nvarchar(500) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_rate_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_rate_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_billing_rate PRIMARY KEY CLUSTERED (rate_id ASC),

        CONSTRAINT UX_billing_rate_code UNIQUE NONCLUSTERED (rate_code ASC),

        CONSTRAINT CK_billing_rate_effective CHECK (effective_to IS NULL OR effective_to >= effective_from)

    );



    CREATE INDEX IX_billing_rate_effective ON dbo.billing_rate(effective_from ASC, effective_to ASC, is_active ASC);

END

GO



IF OBJECT_ID(N'dbo.tenant_billing_contract', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.tenant_billing_contract (

        contract_id bigint IDENTITY(1,1) NOT NULL,

        store_id int NOT NULL,

        rate_id int NOT NULL,

        contract_start_date date NOT NULL,

        contract_end_date date NULL,

        contracted_demand_kw decimal(18,3) NULL,

        billing_day tinyint NULL,

        shared_area_ratio decimal(9,6) NOT NULL CONSTRAINT DF_tenant_billing_contract_shared_ratio DEFAULT ((0)),

        is_active bit NOT NULL CONSTRAINT DF_tenant_billing_contract_active DEFAULT ((1)),

        notes nvarchar(500) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_billing_contract_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_tenant_billing_contract_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_tenant_billing_contract PRIMARY KEY CLUSTERED (contract_id ASC),

        CONSTRAINT FK_tenant_billing_contract_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),

        CONSTRAINT FK_tenant_billing_contract_rate FOREIGN KEY (rate_id) REFERENCES dbo.billing_rate(rate_id),

        CONSTRAINT CK_tenant_billing_contract_dates CHECK (contract_end_date IS NULL OR contract_end_date >= contract_start_date)

    );



    CREATE INDEX IX_tenant_billing_contract_store_dates ON dbo.tenant_billing_contract(store_id ASC, contract_start_date ASC, contract_end_date ASC, is_active ASC);

END

GO



IF OBJECT_ID(N'dbo.billing_meter_snapshot', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.billing_meter_snapshot (

        snapshot_id bigint IDENTITY(1,1) NOT NULL,

        cycle_id int NOT NULL,

        store_id int NOT NULL,

        meter_id int NOT NULL,

        snapshot_type varchar(20) NOT NULL,

        snapshot_at datetime2(0) NOT NULL,

        energy_total_kwh decimal(18,3) NOT NULL,

        source_kind varchar(20) NOT NULL CONSTRAINT DF_billing_meter_snapshot_source DEFAULT ('AUTO'),

        source_measurement_time datetime2(0) NULL,

        note nvarchar(300) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_meter_snapshot_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_meter_snapshot_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_billing_meter_snapshot PRIMARY KEY CLUSTERED (snapshot_id ASC),

        CONSTRAINT FK_billing_meter_snapshot_cycle FOREIGN KEY (cycle_id) REFERENCES dbo.billing_cycle(cycle_id),

        CONSTRAINT FK_billing_meter_snapshot_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),

        CONSTRAINT FK_billing_meter_snapshot_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id),

        CONSTRAINT CK_billing_meter_snapshot_type CHECK (snapshot_type IN ('OPENING', 'CLOSING'))

    );



    CREATE UNIQUE INDEX UX_billing_meter_snapshot_cycle_store_meter_type

        ON dbo.billing_meter_snapshot(cycle_id ASC, store_id ASC, meter_id ASC, snapshot_type ASC);

    CREATE INDEX IX_billing_meter_snapshot_meter_time

        ON dbo.billing_meter_snapshot(meter_id ASC, snapshot_at DESC);

END

GO



IF OBJECT_ID(N'dbo.billing_statement', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.billing_statement (

        statement_id bigint IDENTITY(1,1) NOT NULL,

        cycle_id int NOT NULL,

        store_id int NOT NULL,

        contract_id bigint NULL,

        opening_kwh decimal(18,3) NOT NULL CONSTRAINT DF_billing_statement_opening DEFAULT ((0)),

        closing_kwh decimal(18,3) NOT NULL CONSTRAINT DF_billing_statement_closing DEFAULT ((0)),

        usage_kwh decimal(18,3) NOT NULL CONSTRAINT DF_billing_statement_usage DEFAULT ((0)),

        peak_demand_kw decimal(18,3) NULL,

        basic_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_basic DEFAULT ((0)),

        energy_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_energy DEFAULT ((0)),

        demand_charge_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_demand DEFAULT ((0)),

        adjustment_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_adjust DEFAULT ((0)),

        vat_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_vat DEFAULT ((0)),

        fund_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_fund DEFAULT ((0)),

        total_amount decimal(18,2) NOT NULL CONSTRAINT DF_billing_statement_total DEFAULT ((0)),

        statement_status varchar(20) NOT NULL CONSTRAINT DF_billing_statement_status DEFAULT ('DRAFT'),

        issued_at datetime2(0) NULL,

        confirmed_at datetime2(0) NULL,

        notes nvarchar(500) NULL,

        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_statement_created_at DEFAULT (sysdatetime()),

        updated_at datetime2(0) NOT NULL CONSTRAINT DF_billing_statement_updated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_billing_statement PRIMARY KEY CLUSTERED (statement_id ASC),

        CONSTRAINT FK_billing_statement_cycle FOREIGN KEY (cycle_id) REFERENCES dbo.billing_cycle(cycle_id),

        CONSTRAINT FK_billing_statement_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),

        CONSTRAINT FK_billing_statement_contract FOREIGN KEY (contract_id) REFERENCES dbo.tenant_billing_contract(contract_id),

        CONSTRAINT UX_billing_statement_cycle_store UNIQUE NONCLUSTERED (cycle_id ASC, store_id ASC)

    );



    CREATE INDEX IX_billing_statement_status ON dbo.billing_statement(statement_status ASC, cycle_id ASC);

END

GO



IF OBJECT_ID(N'dbo.billing_statement_line', N'U') IS NULL

BEGIN

    CREATE TABLE dbo.billing_statement_line (

        line_id bigint IDENTITY(1,1) NOT NULL,

        statement_id bigint NOT NULL,

        line_type varchar(30) NOT NULL,

        description nvarchar(200) NOT NULL,

        quantity decimal(18,3) NULL,

        unit_price decimal(18,4) NULL,

        amount decimal(18,2) NOT NULL,

        sort_order int NOT NULL CONSTRAINT DF_billing_statement_line_sort DEFAULT ((0)),

        created_at datetime2(0) NOT NULL CONSTRAINT DF_billing_statement_line_created_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_billing_statement_line PRIMARY KEY CLUSTERED (line_id ASC),

        CONSTRAINT FK_billing_statement_line_statement FOREIGN KEY (statement_id) REFERENCES dbo.billing_statement(statement_id)

    );



    CREATE INDEX IX_billing_statement_line_statement ON dbo.billing_statement_line(statement_id ASC, sort_order ASC);

END

GO



IF OBJECT_ID(N'dbo.vw_tenant_billing_meter_usage', N'V') IS NULL

EXEC('

CREATE VIEW dbo.vw_tenant_billing_meter_usage

AS

SELECT

    ts.store_id,

    ts.store_code,

    ts.store_name,

    tm.map_id,

    tm.billing_scope,

    tm.allocation_ratio,

    tm.valid_from,

    tm.valid_to,

    m.meter_id,

    m.name AS meter_name,

    m.panel_name,

    m.building_name,

    m.usage_type

FROM dbo.tenant_meter_map tm

INNER JOIN dbo.tenant_store ts ON ts.store_id = tm.store_id

INNER JOIN dbo.meters m ON m.meter_id = tm.meter_id;

');

GO



IF OBJECT_ID(N'dbo.sp_generate_billing_meter_snapshot', N'P') IS NULL

EXEC('

CREATE PROCEDURE dbo.sp_generate_billing_meter_snapshot

    @cycle_id int,

    @snapshot_type varchar(20)

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @target_date datetime2(0);



    SELECT @target_date =

        CASE

            WHEN @snapshot_type = ''OPENING'' THEN CAST(cycle_start_date AS datetime2(0))

            WHEN @snapshot_type = ''CLOSING'' THEN DATEADD(second, -1, DATEADD(day, 1, CAST(cycle_end_date AS datetime2(0))))

            ELSE NULL

        END

    FROM dbo.billing_cycle

    WHERE cycle_id = @cycle_id;



    IF @target_date IS NULL

    BEGIN

        THROW 52000, ''Invalid cycle or snapshot type.'', 1;

    END;



    ;WITH active_map AS (

        SELECT

            tm.store_id,

            tm.meter_id,

            tm.allocation_ratio

        FROM dbo.tenant_meter_map tm

        INNER JOIN dbo.billing_cycle bc

            ON bc.cycle_id = @cycle_id

        WHERE tm.valid_from <= bc.cycle_end_date

          AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date)

    ),

    picked AS (

        SELECT

            am.store_id,

            am.meter_id,

            am.allocation_ratio,

            ms.measured_at,

            CAST(ms.energy_consumed_total AS decimal(18,3)) AS energy_total_kwh,

            ROW_NUMBER() OVER (

                PARTITION BY am.store_id, am.meter_id

                ORDER BY ABS(DATEDIFF(second, ms.measured_at, @target_date)) ASC, ms.measured_at DESC

            ) AS rn

        FROM active_map am

        INNER JOIN dbo.measurements ms

            ON ms.meter_id = am.meter_id

        WHERE ms.energy_consumed_total IS NOT NULL

          AND ms.measured_at BETWEEN DATEADD(day, -3, @target_date) AND DATEADD(day, 3, @target_date)

    )

    MERGE dbo.billing_meter_snapshot AS t

    USING (

        SELECT

            @cycle_id AS cycle_id,

            p.store_id,

            p.meter_id,

            @snapshot_type AS snapshot_type,

            p.measured_at AS snapshot_at,

            CAST(p.energy_total_kwh * p.allocation_ratio AS decimal(18,3)) AS energy_total_kwh,

            p.measured_at AS source_measurement_time

        FROM picked p

        WHERE p.rn = 1

    ) AS s

    ON t.cycle_id = s.cycle_id

       AND t.store_id = s.store_id

       AND t.meter_id = s.meter_id

       AND t.snapshot_type = s.snapshot_type

    WHEN MATCHED THEN

        UPDATE SET

            snapshot_at = s.snapshot_at,

            energy_total_kwh = s.energy_total_kwh,

            source_kind = ''AUTO'',

            source_measurement_time = s.source_measurement_time,

            updated_at = sysdatetime()

    WHEN NOT MATCHED THEN

        INSERT (cycle_id, store_id, meter_id, snapshot_type, snapshot_at, energy_total_kwh, source_kind, source_measurement_time)

        VALUES (s.cycle_id, s.store_id, s.meter_id, s.snapshot_type, s.snapshot_at, s.energy_total_kwh, ''AUTO'', s.source_measurement_time);

END

');

GO



IF OBJECT_ID(N'dbo.sp_generate_billing_statement', N'P') IS NULL

EXEC('

CREATE PROCEDURE dbo.sp_generate_billing_statement

    @cycle_id int

AS

BEGIN

    SET NOCOUNT ON;



    ;WITH contract_pick AS (

        SELECT

            bc.cycle_id,

            c.store_id,

            c.contract_id,

            c.contracted_demand_kw,

            r.rate_id,

            r.basic_charge_amount,

            r.unit_price_per_kwh,

            r.demand_unit_price,

            r.vat_rate,

            r.fund_rate,

            ROW_NUMBER() OVER (

                PARTITION BY c.store_id

                ORDER BY c.contract_start_date DESC, c.contract_id DESC

            ) AS rn

        FROM dbo.billing_cycle bc

        INNER JOIN dbo.tenant_billing_contract c

            ON c.contract_start_date <= bc.cycle_end_date

           AND (c.contract_end_date IS NULL OR c.contract_end_date >= bc.cycle_start_date)

           AND c.is_active = 1

        INNER JOIN dbo.billing_rate r

            ON r.rate_id = c.rate_id

           AND r.effective_from <= bc.cycle_end_date

           AND (r.effective_to IS NULL OR r.effective_to >= bc.cycle_start_date)

           AND r.is_active = 1

        WHERE bc.cycle_id = @cycle_id

    ),

    openings AS (

        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS opening_kwh

        FROM dbo.billing_meter_snapshot

        WHERE cycle_id = @cycle_id AND snapshot_type = ''OPENING''

        GROUP BY cycle_id, store_id

    ),

    closings AS (

        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS closing_kwh

        FROM dbo.billing_meter_snapshot

        WHERE cycle_id = @cycle_id AND snapshot_type = ''CLOSING''

        GROUP BY cycle_id, store_id

    ),

    peak AS (

        SELECT

            tm.store_id,

            MAX(CAST(ms.active_power_total AS decimal(18,3)) * tm.allocation_ratio) AS peak_demand_kw

        FROM dbo.billing_cycle bc

        INNER JOIN dbo.tenant_meter_map tm

            ON tm.valid_from <= bc.cycle_end_date

           AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date)

        INNER JOIN dbo.measurements ms

            ON ms.meter_id = tm.meter_id

           AND ms.measured_at >= bc.cycle_start_date

           AND ms.measured_at < DATEADD(day, 1, bc.cycle_end_date)

        WHERE bc.cycle_id = @cycle_id

          AND ms.active_power_total IS NOT NULL

        GROUP BY tm.store_id

    )

    MERGE dbo.billing_statement AS t

    USING (

        SELECT

            cp.cycle_id,

            cp.store_id,

            cp.contract_id,

            ISNULL(o.opening_kwh, 0) AS opening_kwh,

            ISNULL(c.closing_kwh, 0) AS closing_kwh,

            CASE

                WHEN ISNULL(c.closing_kwh, 0) >= ISNULL(o.opening_kwh, 0)

                    THEN ISNULL(c.closing_kwh, 0) - ISNULL(o.opening_kwh, 0)

                ELSE 0

            END AS usage_kwh,

            p.peak_demand_kw,

            cp.basic_charge_amount,

            CAST(CASE

                WHEN ISNULL(c.closing_kwh, 0) >= ISNULL(o.opening_kwh, 0)

                    THEN (ISNULL(c.closing_kwh, 0) - ISNULL(o.opening_kwh, 0)) * cp.unit_price_per_kwh

                ELSE 0

            END AS decimal(18,2)) AS energy_charge_amount,

            CAST(ISNULL(p.peak_demand_kw, ISNULL(cp.contracted_demand_kw, 0)) * cp.demand_unit_price AS decimal(18,2)) AS demand_charge_amount,

            cp.vat_rate,

            cp.fund_rate

        FROM contract_pick cp

        LEFT JOIN openings o ON o.cycle_id = cp.cycle_id AND o.store_id = cp.store_id

        LEFT JOIN closings c ON c.cycle_id = cp.cycle_id AND c.store_id = cp.store_id

        LEFT JOIN peak p ON p.store_id = cp.store_id

        WHERE cp.rn = 1

    ) AS s

    ON t.cycle_id = s.cycle_id AND t.store_id = s.store_id

    WHEN MATCHED THEN

        UPDATE SET

            contract_id = s.contract_id,

            opening_kwh = s.opening_kwh,

            closing_kwh = s.closing_kwh,

            usage_kwh = s.usage_kwh,

            peak_demand_kw = s.peak_demand_kw,

            basic_charge_amount = s.basic_charge_amount,

            energy_charge_amount = s.energy_charge_amount,

            demand_charge_amount = s.demand_charge_amount,

            adjustment_amount = ISNULL(t.adjustment_amount, 0),

            vat_amount = CAST((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)) * s.vat_rate AS decimal(18,2)),

            fund_amount = CAST((s.energy_charge_amount) * s.fund_rate AS decimal(18,2)),

            total_amount = CAST(

                s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)

                + ((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)) * s.vat_rate)

                + ((s.energy_charge_amount) * s.fund_rate)

                AS decimal(18,2)

            ),

            updated_at = sysdatetime()

    WHEN NOT MATCHED THEN

        INSERT (

            cycle_id, store_id, contract_id, opening_kwh, closing_kwh, usage_kwh, peak_demand_kw,

            basic_charge_amount, energy_charge_amount, demand_charge_amount, adjustment_amount,

            vat_amount, fund_amount, total_amount

        )

        VALUES (

            s.cycle_id, s.store_id, s.contract_id, s.opening_kwh, s.closing_kwh, s.usage_kwh, s.peak_demand_kw,

            s.basic_charge_amount, s.energy_charge_amount, s.demand_charge_amount, 0,

            CAST((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount) * s.vat_rate AS decimal(18,2)),

            CAST((s.energy_charge_amount) * s.fund_rate AS decimal(18,2)),

            CAST(

                s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount

                + ((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount) * s.vat_rate)

                + ((s.energy_charge_amount) * s.fund_rate)

                AS decimal(18,2)

            )

        );

END

');

GO

/* ===== END create_epms_tenant_billing_schema.sql ===== */



PRINT '--- 11. alter_epms_tenant_billing_for_store_open_close.sql ---';

GO

/* ===== BEGIN alter_epms_tenant_billing_for_store_open_close.sql ===== */

USE [epms];

GO



ALTER PROCEDURE dbo.sp_generate_billing_meter_snapshot

    @cycle_id int,

    @snapshot_type varchar(20)

AS

BEGIN

    SET NOCOUNT ON;



    IF @snapshot_type NOT IN ('OPENING', 'CLOSING')

    BEGIN

        THROW 52000, 'Invalid snapshot type.', 1;

    END;



    ;WITH scoped AS (

        SELECT

            tm.store_id,

            tm.meter_id,

            tm.allocation_ratio,

            CASE

                WHEN ts.opened_on IS NULL OR ts.opened_on < bc.cycle_start_date THEN bc.cycle_start_date

                ELSE ts.opened_on

            END AS effective_start_date,

            CASE

                WHEN ts.closed_on IS NULL OR ts.closed_on > bc.cycle_end_date THEN bc.cycle_end_date

                ELSE ts.closed_on

            END AS effective_end_date

        FROM dbo.tenant_meter_map tm

        INNER JOIN dbo.tenant_store ts

            ON ts.store_id = tm.store_id

        INNER JOIN dbo.billing_cycle bc

            ON bc.cycle_id = @cycle_id

        WHERE tm.valid_from <= bc.cycle_end_date

          AND (tm.valid_to IS NULL OR tm.valid_to >= bc.cycle_start_date)

          AND (ts.closed_on IS NULL OR ts.closed_on >= bc.cycle_start_date)

          AND (ts.opened_on IS NULL OR ts.opened_on <= bc.cycle_end_date)

    ),

    bounded AS (

        SELECT

            store_id,

            meter_id,

            allocation_ratio,

            effective_start_date,

            effective_end_date,

            CASE

                WHEN @snapshot_type = 'OPENING' THEN CAST(effective_start_date AS datetime2(0))

                ELSE DATEADD(second, -1, DATEADD(day, 1, CAST(effective_end_date AS datetime2(0))))

            END AS target_dt

        FROM scoped

        WHERE effective_end_date >= effective_start_date

    ),

    picked AS (

        SELECT

            b.store_id,

            b.meter_id,

            b.allocation_ratio,

            ms.measured_at,

            CAST(ms.energy_consumed_total AS decimal(18,3)) AS energy_total_kwh,

            ROW_NUMBER() OVER (

                PARTITION BY b.store_id, b.meter_id

                ORDER BY ABS(DATEDIFF(second, ms.measured_at, b.target_dt)) ASC, ms.measured_at DESC

            ) AS rn

        FROM bounded b

        INNER JOIN dbo.measurements ms

            ON ms.meter_id = b.meter_id

        WHERE ms.energy_consumed_total IS NOT NULL

          AND ms.measured_at BETWEEN DATEADD(day, -3, b.target_dt) AND DATEADD(day, 3, b.target_dt)

    )

    MERGE dbo.billing_meter_snapshot AS t

    USING (

        SELECT

            @cycle_id AS cycle_id,

            p.store_id,

            p.meter_id,

            @snapshot_type AS snapshot_type,

            p.measured_at AS snapshot_at,

            CAST(p.energy_total_kwh * p.allocation_ratio AS decimal(18,3)) AS energy_total_kwh,

            p.measured_at AS source_measurement_time

        FROM picked p

        WHERE p.rn = 1

    ) AS s

    ON t.cycle_id = s.cycle_id

       AND t.store_id = s.store_id

       AND t.meter_id = s.meter_id

       AND t.snapshot_type = s.snapshot_type

    WHEN MATCHED THEN

        UPDATE SET

            snapshot_at = s.snapshot_at,

            energy_total_kwh = s.energy_total_kwh,

            source_kind = 'AUTO',

            source_measurement_time = s.source_measurement_time,

            updated_at = sysdatetime()

    WHEN NOT MATCHED THEN

        INSERT (cycle_id, store_id, meter_id, snapshot_type, snapshot_at, energy_total_kwh, source_kind, source_measurement_time)

        VALUES (s.cycle_id, s.store_id, s.meter_id, s.snapshot_type, s.snapshot_at, s.energy_total_kwh, 'AUTO', s.source_measurement_time);

END

GO



ALTER PROCEDURE dbo.sp_generate_billing_statement

    @cycle_id int

AS

BEGIN

    SET NOCOUNT ON;



    ;WITH cycle_window AS (

        SELECT cycle_id, cycle_start_date, cycle_end_date

        FROM dbo.billing_cycle

        WHERE cycle_id = @cycle_id

    ),

    store_window AS (

        SELECT

            ts.store_id,

            CASE

                WHEN ts.opened_on IS NULL OR ts.opened_on < cw.cycle_start_date THEN cw.cycle_start_date

                ELSE ts.opened_on

            END AS effective_start_date,

            CASE

                WHEN ts.closed_on IS NULL OR ts.closed_on > cw.cycle_end_date THEN cw.cycle_end_date

                ELSE ts.closed_on

            END AS effective_end_date

        FROM dbo.tenant_store ts

        CROSS JOIN cycle_window cw

        WHERE (ts.closed_on IS NULL OR ts.closed_on >= cw.cycle_start_date)

          AND (ts.opened_on IS NULL OR ts.opened_on <= cw.cycle_end_date)

    ),

    valid_store_window AS (

        SELECT store_id, effective_start_date, effective_end_date

        FROM store_window

        WHERE effective_end_date >= effective_start_date

    ),

    contract_pick AS (

        SELECT

            cw.cycle_id,

            c.store_id,

            c.contract_id,

            c.contracted_demand_kw,

            r.rate_id,

            r.basic_charge_amount,

            r.unit_price_per_kwh,

            r.demand_unit_price,

            r.vat_rate,

            r.fund_rate,

            ROW_NUMBER() OVER (

                PARTITION BY c.store_id

                ORDER BY c.contract_start_date DESC, c.contract_id DESC

            ) AS rn

        FROM cycle_window cw

        INNER JOIN valid_store_window sw

            ON 1 = 1

        INNER JOIN dbo.tenant_billing_contract c

            ON c.store_id = sw.store_id

           AND c.contract_start_date <= sw.effective_end_date

           AND (c.contract_end_date IS NULL OR c.contract_end_date >= sw.effective_start_date)

           AND c.is_active = 1

        INNER JOIN dbo.billing_rate r

            ON r.rate_id = c.rate_id

           AND r.effective_from <= sw.effective_end_date

           AND (r.effective_to IS NULL OR r.effective_to >= sw.effective_start_date)

           AND r.is_active = 1

    ),

    openings AS (

        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS opening_kwh

        FROM dbo.billing_meter_snapshot

        WHERE cycle_id = @cycle_id AND snapshot_type = 'OPENING'

        GROUP BY cycle_id, store_id

    ),

    closings AS (

        SELECT cycle_id, store_id, SUM(energy_total_kwh) AS closing_kwh

        FROM dbo.billing_meter_snapshot

        WHERE cycle_id = @cycle_id AND snapshot_type = 'CLOSING'

        GROUP BY cycle_id, store_id

    ),

    peak AS (

        SELECT

            tm.store_id,

            MAX(CAST(ms.active_power_total AS decimal(18,3)) * tm.allocation_ratio) AS peak_demand_kw

        FROM valid_store_window sw

        INNER JOIN dbo.tenant_meter_map tm

            ON tm.store_id = sw.store_id

           AND tm.valid_from <= sw.effective_end_date

           AND (tm.valid_to IS NULL OR tm.valid_to >= sw.effective_start_date)

        INNER JOIN dbo.measurements ms

            ON ms.meter_id = tm.meter_id

           AND ms.measured_at >= sw.effective_start_date

           AND ms.measured_at < DATEADD(day, 1, sw.effective_end_date)

        WHERE ms.active_power_total IS NOT NULL

        GROUP BY tm.store_id

    )

    MERGE dbo.billing_statement AS t

    USING (

        SELECT

            cp.cycle_id,

            cp.store_id,

            cp.contract_id,

            ISNULL(o.opening_kwh, 0) AS opening_kwh,

            ISNULL(c.closing_kwh, 0) AS closing_kwh,

            CASE

                WHEN ISNULL(c.closing_kwh, 0) >= ISNULL(o.opening_kwh, 0)

                    THEN ISNULL(c.closing_kwh, 0) - ISNULL(o.opening_kwh, 0)

                ELSE 0

            END AS usage_kwh,

            p.peak_demand_kw,

            cp.basic_charge_amount,

            CAST(CASE

                WHEN ISNULL(c.closing_kwh, 0) >= ISNULL(o.opening_kwh, 0)

                    THEN (ISNULL(c.closing_kwh, 0) - ISNULL(o.opening_kwh, 0)) * cp.unit_price_per_kwh

                ELSE 0

            END AS decimal(18,2)) AS energy_charge_amount,

            CAST(ISNULL(p.peak_demand_kw, ISNULL(cp.contracted_demand_kw, 0)) * cp.demand_unit_price AS decimal(18,2)) AS demand_charge_amount,

            cp.vat_rate,

            cp.fund_rate

        FROM contract_pick cp

        LEFT JOIN openings o ON o.cycle_id = cp.cycle_id AND o.store_id = cp.store_id

        LEFT JOIN closings c ON c.cycle_id = cp.cycle_id AND c.store_id = cp.store_id

        LEFT JOIN peak p ON p.store_id = cp.store_id

        WHERE cp.rn = 1

    ) AS s

    ON t.cycle_id = s.cycle_id AND t.store_id = s.store_id

    WHEN MATCHED THEN

        UPDATE SET

            contract_id = s.contract_id,

            opening_kwh = s.opening_kwh,

            closing_kwh = s.closing_kwh,

            usage_kwh = s.usage_kwh,

            peak_demand_kw = s.peak_demand_kw,

            basic_charge_amount = s.basic_charge_amount,

            energy_charge_amount = s.energy_charge_amount,

            demand_charge_amount = s.demand_charge_amount,

            adjustment_amount = ISNULL(t.adjustment_amount, 0),

            vat_amount = CAST((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)) * s.vat_rate AS decimal(18,2)),

            fund_amount = CAST((s.energy_charge_amount) * s.fund_rate AS decimal(18,2)),

            total_amount = CAST(

                s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)

                + ((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount + ISNULL(t.adjustment_amount, 0)) * s.vat_rate)

                + ((s.energy_charge_amount) * s.fund_rate)

                AS decimal(18,2)

            ),

            updated_at = sysdatetime()

    WHEN NOT MATCHED THEN

        INSERT (

            cycle_id, store_id, contract_id, opening_kwh, closing_kwh, usage_kwh, peak_demand_kw,

            basic_charge_amount, energy_charge_amount, demand_charge_amount, adjustment_amount,

            vat_amount, fund_amount, total_amount

        )

        VALUES (

            s.cycle_id, s.store_id, s.contract_id, s.opening_kwh, s.closing_kwh, s.usage_kwh, s.peak_demand_kw,

            s.basic_charge_amount, s.energy_charge_amount, s.demand_charge_amount, 0,

            CAST((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount) * s.vat_rate AS decimal(18,2)),

            CAST((s.energy_charge_amount) * s.fund_rate AS decimal(18,2)),

            CAST(

                s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount

                + ((s.basic_charge_amount + s.energy_charge_amount + s.demand_charge_amount) * s.vat_rate)

                + ((s.energy_charge_amount) * s.fund_rate)

                AS decimal(18,2)

            )

        );

END

GO

/* ===== END alter_epms_tenant_billing_for_store_open_close.sql ===== */



PRINT '--- 12. create_epms_peak_policy_schema.sql ---';

GO

/* ===== BEGIN create_epms_peak_policy_schema.sql ===== */

IF OBJECT_ID('dbo.peak_policy_master', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.peak_policy_master (

        policy_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,

        policy_name NVARCHAR(200) NOT NULL,

        peak_limit_kw FLOAT NOT NULL,

        warning_threshold_pct FLOAT NOT NULL,

        control_threshold_pct FLOAT NOT NULL,

        priority_level INT NOT NULL CONSTRAINT DF_peak_policy_master_priority_level DEFAULT (5),

        control_enabled BIT NOT NULL CONSTRAINT DF_peak_policy_master_control_enabled DEFAULT (0),

        effective_from DATE NOT NULL,

        effective_to DATE NULL,

        notes NVARCHAR(1000) NULL,

        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_master_created_at DEFAULT (SYSDATETIME()),

        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_master_updated_at DEFAULT (SYSDATETIME()),

        CONSTRAINT CK_peak_policy_master_peak_limit_kw CHECK (peak_limit_kw > 0),

        CONSTRAINT CK_peak_policy_master_warning_pct CHECK (warning_threshold_pct > 0 AND warning_threshold_pct <= 100),

        CONSTRAINT CK_peak_policy_master_control_pct CHECK (control_threshold_pct > 0 AND control_threshold_pct <= 100),

        CONSTRAINT CK_peak_policy_master_priority_level CHECK (priority_level BETWEEN 1 AND 9),

        CONSTRAINT CK_peak_policy_master_date_range CHECK (effective_to IS NULL OR effective_to >= effective_from),

        CONSTRAINT CK_peak_policy_master_threshold_order CHECK (warning_threshold_pct <= control_threshold_pct)

    );

END;



IF OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.peak_policy_store_map (

        map_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,

        policy_id BIGINT NOT NULL,

        store_id INT NOT NULL,

        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_store_map_created_at DEFAULT (SYSDATETIME()),

        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_policy_store_map_updated_at DEFAULT (SYSDATETIME()),

        CONSTRAINT FK_peak_policy_store_map_policy FOREIGN KEY (policy_id) REFERENCES dbo.peak_policy_master(policy_id),

        CONSTRAINT FK_peak_policy_store_map_store FOREIGN KEY (store_id) REFERENCES dbo.tenant_store(store_id),

        CONSTRAINT UQ_peak_policy_store_map UNIQUE (policy_id, store_id)

    );

END;



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE name = 'IX_peak_policy_master_effective'

      AND object_id = OBJECT_ID('dbo.peak_policy_master')

)

BEGIN

    CREATE INDEX IX_peak_policy_master_effective

        ON dbo.peak_policy_master (effective_from DESC, effective_to, priority_level);

END;



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE name = 'IX_peak_policy_store_map_store'

      AND object_id = OBJECT_ID('dbo.peak_policy_store_map')

)

BEGIN

    CREATE INDEX IX_peak_policy_store_map_store

        ON dbo.peak_policy_store_map (store_id, policy_id);

END;



IF OBJECT_ID('dbo.peak_policy', 'U') IS NOT NULL

AND NOT EXISTS (SELECT 1 FROM dbo.peak_policy_master)

BEGIN

    INSERT INTO dbo.peak_policy_master (

        policy_name, peak_limit_kw, warning_threshold_pct, control_threshold_pct,

        priority_level, control_enabled, effective_from, effective_to, notes, created_at, updated_at

    )

    SELECT

        ts.store_code + N' 기본정책',

        p.peak_limit_kw,

        p.warning_threshold_pct,

        p.control_threshold_pct,

        p.priority_level,

        p.control_enabled,

        p.effective_from,

        p.effective_to,

        p.notes,

        p.created_at,

        p.updated_at

    FROM dbo.peak_policy p

    INNER JOIN dbo.tenant_store ts ON ts.store_id = p.store_id

    ORDER BY p.policy_id;



    ;WITH legacy_rows AS (

        SELECT

            ROW_NUMBER() OVER (ORDER BY p.policy_id) AS rn,

            p.store_id

        FROM dbo.peak_policy p

    ),

    new_rows AS (

        SELECT

            ROW_NUMBER() OVER (ORDER BY pm.policy_id) AS rn,

            pm.policy_id

        FROM dbo.peak_policy_master pm

    )

    INSERT INTO dbo.peak_policy_store_map (policy_id, store_id)

    SELECT nr.policy_id, lr.store_id

    FROM legacy_rows lr

    INNER JOIN new_rows nr ON nr.rn = lr.rn;

END;

/* ===== END create_epms_peak_policy_schema.sql ===== */



PRINT '--- 13. create_epms_peak_15min_summary.sql ---';

GO

/* ===== BEGIN create_epms_peak_15min_summary.sql ===== */

IF OBJECT_ID('dbo.peak_15min_summary', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.peak_15min_summary (

        summary_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,

        meter_id INT NOT NULL,

        bucket_at DATETIME NOT NULL,

        demand_kw FLOAT NOT NULL,

        sample_count INT NOT NULL CONSTRAINT DF_peak_15min_summary_sample_count DEFAULT (0),

        created_at DATETIME2 NOT NULL CONSTRAINT DF_peak_15min_summary_created_at DEFAULT (SYSDATETIME()),

        updated_at DATETIME2 NOT NULL CONSTRAINT DF_peak_15min_summary_updated_at DEFAULT (SYSDATETIME()),

        CONSTRAINT FK_peak_15min_summary_meter FOREIGN KEY (meter_id) REFERENCES dbo.meters(meter_id),

        CONSTRAINT UQ_peak_15min_summary_meter_bucket UNIQUE (meter_id, bucket_at)

    );

END;

GO



IF NOT EXISTS (

    SELECT 1

    FROM sys.indexes

    WHERE name = 'IX_peak_15min_summary_bucket'

      AND object_id = OBJECT_ID('dbo.peak_15min_summary')

)

BEGIN

    CREATE INDEX IX_peak_15min_summary_bucket

        ON dbo.peak_15min_summary (bucket_at DESC, meter_id)

        INCLUDE (demand_kw, sample_count);

END;

GO



CREATE OR ALTER PROCEDURE dbo.sp_refresh_peak_15min_summary

    @days_back INT = 35

AS

BEGIN

    SET NOCOUNT ON;



    DECLARE @from_at DATETIME = DATEADD(day, -ABS(ISNULL(@days_back, 35)), GETDATE());



    ;WITH src AS (

        SELECT

            ms.meter_id,

            DATEADD(minute, (DATEDIFF(minute, 0, ms.measured_at) / 15) * 15, 0) AS bucket_at,

            AVG(CAST(ms.active_power_total AS FLOAT)) AS demand_kw,

            COUNT(*) AS sample_count

        FROM dbo.measurements ms

        WHERE ms.active_power_total IS NOT NULL

          AND ms.measured_at >= @from_at

        GROUP BY

            ms.meter_id,

            DATEADD(minute, (DATEDIFF(minute, 0, ms.measured_at) / 15) * 15, 0)

    )

    MERGE dbo.peak_15min_summary AS t

    USING src

       ON t.meter_id = src.meter_id

      AND t.bucket_at = src.bucket_at

    WHEN MATCHED THEN

        UPDATE SET

            t.demand_kw = src.demand_kw,

            t.sample_count = src.sample_count,

            t.updated_at = SYSDATETIME()

    WHEN NOT MATCHED THEN

        INSERT (meter_id, bucket_at, demand_kw, sample_count, created_at, updated_at)

        VALUES (src.meter_id, src.bucket_at, src.demand_kw, src.sample_count, SYSDATETIME(), SYSDATETIME());



    DELETE

    FROM dbo.peak_15min_summary

    WHERE bucket_at < @from_at;

END;

GO

/* ===== END create_epms_peak_15min_summary.sql ===== */



PRINT '--- 14. create_epms_carbon_factor_schema.sql ---';

GO

/* ===== BEGIN create_epms_carbon_factor_schema.sql ===== */

IF OBJECT_ID('dbo.epms_carbon_factor', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.epms_carbon_factor (

        factor_code varchar(50) NOT NULL PRIMARY KEY,

        factor_name nvarchar(240) NULL,

        factor_value decimal(12,6) NOT NULL,

        factor_unit varchar(32) NOT NULL CONSTRAINT DF_epms_carbon_factor_unit DEFAULT ('kgCO2_per_kWh'),

        factor_source nvarchar(400) NULL,

        factor_note nvarchar(1000) NULL,

        is_active bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_active DEFAULT (1),

        is_default bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_default DEFAULT (0),

        created_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_created_at DEFAULT (sysdatetime()),

        updated_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_updated_at DEFAULT (sysdatetime())

    );

END

GO



IF COL_LENGTH('dbo.epms_carbon_factor', 'factor_name') IS NULL

    ALTER TABLE dbo.epms_carbon_factor ADD factor_name nvarchar(240) NULL;

GO



ALTER TABLE dbo.epms_carbon_factor ALTER COLUMN factor_name nvarchar(240) NULL;

GO



ALTER TABLE dbo.epms_carbon_factor ALTER COLUMN factor_source nvarchar(400) NULL;

GO



ALTER TABLE dbo.epms_carbon_factor ALTER COLUMN factor_note nvarchar(1000) NULL;

GO



IF COL_LENGTH('dbo.epms_carbon_factor', 'is_active') IS NULL

    ALTER TABLE dbo.epms_carbon_factor ADD is_active bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_active DEFAULT (1);

GO



IF COL_LENGTH('dbo.epms_carbon_factor', 'is_default') IS NULL

    ALTER TABLE dbo.epms_carbon_factor ADD is_default bit NOT NULL CONSTRAINT DF_epms_carbon_factor_is_default DEFAULT (0);

GO



IF COL_LENGTH('dbo.epms_carbon_factor', 'created_at') IS NULL

    ALTER TABLE dbo.epms_carbon_factor ADD created_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_created_at DEFAULT (sysdatetime());

GO



IF OBJECT_ID('dbo.epms_building_carbon_daily', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.epms_building_carbon_daily (

        scope_code varchar(120) NOT NULL,

        building_name nvarchar(400) NULL,

        emission_date date NOT NULL,

        factor_code varchar(50) NULL,

        usage_kwh decimal(18,6) NOT NULL,

        emission_factor decimal(12,6) NOT NULL,

        co2_kg decimal(18,6) NOT NULL,

        factor_source nvarchar(400) NULL,

        factor_note nvarchar(1000) NULL,

        calculated_at datetime2 NOT NULL CONSTRAINT DF_epms_building_carbon_daily_calculated_at DEFAULT (sysdatetime()),

        CONSTRAINT PK_epms_building_carbon_daily PRIMARY KEY (scope_code, emission_date)

    );

END

GO



ALTER TABLE dbo.epms_building_carbon_daily ALTER COLUMN building_name nvarchar(400) NULL;

GO



IF COL_LENGTH('dbo.epms_building_carbon_daily', 'factor_code') IS NULL

    ALTER TABLE dbo.epms_building_carbon_daily ADD factor_code varchar(50) NULL;

GO



ALTER TABLE dbo.epms_building_carbon_daily ALTER COLUMN factor_source nvarchar(400) NULL;

GO



ALTER TABLE dbo.epms_building_carbon_daily ALTER COLUMN factor_note nvarchar(1000) NULL;

GO



IF OBJECT_ID('dbo.epms_carbon_factor_history', 'U') IS NULL

BEGIN

    CREATE TABLE dbo.epms_carbon_factor_history (

        history_id bigint IDENTITY(1,1) NOT NULL PRIMARY KEY,

        factor_code varchar(50) NOT NULL,

        factor_name nvarchar(240) NULL,

        factor_value decimal(12,6) NOT NULL,

        factor_unit varchar(32) NOT NULL,

        factor_source nvarchar(400) NULL,

        factor_note nvarchar(1000) NULL,

        change_action varchar(20) NOT NULL,

        changed_at datetime2 NOT NULL CONSTRAINT DF_epms_carbon_factor_history_changed_at DEFAULT (sysdatetime())

    );

END

GO



IF NOT EXISTS (SELECT 1 FROM dbo.epms_carbon_factor WHERE factor_code = 'DEFAULT_ELECTRICITY')

BEGIN

    INSERT INTO dbo.epms_carbon_factor (

        factor_code,

        factor_name,

        factor_value,

        factor_unit,

        factor_source,

        factor_note,

        is_active,

        is_default

    )

    VALUES (

        'DEFAULT_ELECTRICITY',

        N'Default electricity factor',

        0.450000,

        'kgCO2_per_kWh',

        N'SYSTEM_DEFAULT',

        N'Initial default factor. Update this value to match your reporting standard.',

        1,

        1

    );

END

GO

/* ===== END create_epms_carbon_factor_schema.sql ===== */



PRINT '=== EPMS SQL All-In-One Runner: default sections complete ===';

GO



/*

===============================================================================

Optional sections

- Uncomment and run only when needed.

===============================================================================



PRINT '--- Optional. create_aggregate_agent_jobs.sql ---';

GO

/* ===== BEGIN create_aggregate_agent_jobs.sql =====

/*

   SQL Server Agent jobs for EPMS aggregate measurements



   Purpose

   - Hourly aggregation every 15 minutes

   - Daily rollup at 00:10

   - Monthly rollup on day 1

   - Yearly rollup on Jan 1



   Usage

   1. Open this script in SSMS.

   2. Adjust @TargetDb if your EPMS database name is not EPMS.

   3. Execute against msdb.



   Notes

   - Safe to re-run. Existing jobs with the same names are dropped and recreated.

   - Requires SQL Server Agent and permission to manage Agent jobs.

*/



USE msdb;

GO



DECLARE @TargetDb sysname = N'EPMS';

DECLARE @HourlyJobName sysname = N'EPMS Aggregate Hourly';

DECLARE @RollupJobName sysname = N'EPMS Aggregate Rollup';



DECLARE @HourlyCommand nvarchar(max) =

    N'USE ' + QUOTENAME(@TargetDb) + N';' + CHAR(13) + CHAR(10) +

    N'EXEC dbo.sp_aggregate_hourly_measurements;';



DECLARE @RollupCommand nvarchar(max) =

    N'USE ' + QUOTENAME(@TargetDb) + N';' + CHAR(13) + CHAR(10) +

    N'EXEC dbo.sp_aggregate_daily_measurements;' + CHAR(13) + CHAR(10) +

    N'IF DAY(GETDATE()) = 1 EXEC dbo.sp_aggregate_monthly_measurements;' + CHAR(13) + CHAR(10) +

    N'IF MONTH(GETDATE()) = 1 AND DAY(GETDATE()) = 1 EXEC dbo.sp_aggregate_yearly_measurements;';



IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @HourlyJobName)

BEGIN

    EXEC msdb.dbo.sp_delete_job @job_name = @HourlyJobName, @delete_unused_schedule = 1;

END



IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @RollupJobName)

BEGIN

    EXEC msdb.dbo.sp_delete_job @job_name = @RollupJobName, @delete_unused_schedule = 1;

END



EXEC msdb.dbo.sp_add_job

    @job_name = @HourlyJobName,

    @enabled = 1,

    @description = N'Run EPMS hourly aggregation every 15 minutes.',

    @category_name = N'[Uncategorized (Local)]';



EXEC msdb.dbo.sp_add_jobstep

    @job_name = @HourlyJobName,

    @step_name = N'Aggregate Hourly Measurements',

    @subsystem = N'TSQL',

    @database_name = N'master',

    @command = @HourlyCommand,

    @on_success_action = 1,

    @on_fail_action = 2;



EXEC msdb.dbo.sp_add_jobschedule

    @job_name = @HourlyJobName,

    @name = N'Every 15 Minutes',

    @enabled = 1,

    @freq_type = 4,

    @freq_interval = 1,

    @freq_subday_type = 4,

    @freq_subday_interval = 15,

    @active_start_date = 20260403,

    @active_start_time = 000000;



EXEC msdb.dbo.sp_add_jobserver

    @job_name = @HourlyJobName,

    @server_name = N'(local)';



EXEC msdb.dbo.sp_add_job

    @job_name = @RollupJobName,

    @enabled = 1,

    @description = N'Run EPMS daily rollup aggregation and execute monthly/yearly rollups when applicable.',

    @category_name = N'[Uncategorized (Local)]';



EXEC msdb.dbo.sp_add_jobstep

    @job_name = @RollupJobName,

    @step_name = N'Aggregate Daily Monthly Yearly Measurements',

    @subsystem = N'TSQL',

    @database_name = N'master',

    @command = @RollupCommand,

    @on_success_action = 1,

    @on_fail_action = 2;



EXEC msdb.dbo.sp_add_jobschedule

    @job_name = @RollupJobName,

    @name = N'Daily 00:10',

    @enabled = 1,

    @freq_type = 4,

    @freq_interval = 1,

    @active_start_date = 20260404,

    @active_start_time = 001000;



EXEC msdb.dbo.sp_add_jobserver

    @job_name = @RollupJobName,

    @server_name = N'(local)';



SELECT

    name,

    enabled,

    description

FROM msdb.dbo.sysjobs

WHERE name IN (@HourlyJobName, @RollupJobName)

ORDER BY name;

GO

===== END create_aggregate_agent_jobs.sql ===== */



PRINT '--- Optional. create_peak_15min_summary_agent_job.sql ---';

GO

/* ===== BEGIN create_peak_15min_summary_agent_job.sql =====

/*

   SQL Server Agent job for EPMS peak 15-minute demand summary



   Purpose

   - Refresh dbo.peak_15min_summary on a short interval

   - Keep Peak management dashboard on pre-aggregated data



   Usage

   1. Open this script in SSMS.

   2. Adjust @TargetDb if your EPMS database name is not EPMS.

   3. Execute against msdb.



   Notes

   - Safe to re-run. Existing job with the same name is dropped and recreated.

   - Requires dbo.sp_refresh_peak_15min_summary to exist in the target database.

   - Recommended schedule: every 15 minutes.

*/



USE msdb;

GO



DECLARE @TargetDb sysname = N'EPMS';

DECLARE @JobName sysname = N'EPMS Peak 15Min Summary Refresh';



DECLARE @Command nvarchar(max) =

    N'USE ' + QUOTENAME(@TargetDb) + N';' + CHAR(13) + CHAR(10) +

    N'EXEC dbo.sp_refresh_peak_15min_summary @days_back = 35;';



IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)

BEGIN

    EXEC msdb.dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;

END



EXEC msdb.dbo.sp_add_job

    @job_name = @JobName,

    @enabled = 1,

    @description = N'Refresh EPMS 15-minute peak demand summary every 15 minutes.',

    @category_name = N'[Uncategorized (Local)]';



EXEC msdb.dbo.sp_add_jobstep

    @job_name = @JobName,

    @step_name = N'Refresh Peak 15Min Summary',

    @subsystem = N'TSQL',

    @database_name = N'master',

    @command = @Command,

    @on_success_action = 1,

    @on_fail_action = 2;



EXEC msdb.dbo.sp_add_jobschedule

    @job_name = @JobName,

    @name = N'Every 15 Minutes',

    @enabled = 1,

    @freq_type = 4,

    @freq_interval = 1,

    @freq_subday_type = 4,

    @freq_subday_interval = 15,

    @active_start_date = 20260417,

    @active_start_time = 000000;



EXEC msdb.dbo.sp_add_jobserver

    @job_name = @JobName,

    @server_name = N'(local)';



SELECT

    name,

    enabled,

    description

FROM msdb.dbo.sysjobs

WHERE name = @JobName;

GO

===== END create_peak_15min_summary_agent_job.sql ===== */



PRINT '--- Optional. create_epms_daily_backup_job.sql ---';

GO

/* ===== BEGIN create_epms_daily_backup_job.sql =====

/*

  Create SQL Server Agent job for EPMS daily full backup.

  Default schedule: every day at 02:00.

  The job runs the local PowerShell script:

    C:\Tomcat 9.0\webapps\ROOT\scripts\backup_epms_daily.ps1



  Edit the variables in the next block before running on a new server.

*/



USE [msdb];

GO



DECLARE @jobName sysname = N'EPMS Daily Full Backup';

DECLARE @scriptPath nvarchar(4000) = N'C:\Tomcat 9.0\webapps\ROOT\scripts\backup_epms_daily.ps1';

DECLARE @dbServer nvarchar(4000) = N'localhost,1433';

DECLARE @dbName nvarchar(4000) = N'EPMS';

DECLARE @dbUser nvarchar(4000) = N'';

DECLARE @dbPassword nvarchar(4000) = N'';



IF NULLIF(LTRIM(RTRIM(@dbUser)), N'') IS NULL

   OR NULLIF(LTRIM(RTRIM(@dbPassword)), N'') IS NULL

BEGIN

    THROW 51000, 'Set @dbUser and @dbPassword before creating the backup job.', 1;

END;

DECLARE @backupDir nvarchar(4000) = N'C:\backup';

DECLARE @retainDays int = 7;

DECLARE @startTime int = 020000;

DECLARE @scheduleName sysname = N'EPMS Daily 0200';

DECLARE @command nvarchar(max) =

    N'powershell -NoProfile -ExecutionPolicy Bypass -File "' + @scriptPath +

    N'" -Server "' + @dbServer +

    N'" -Database "' + @dbName +

    N'" -User "' + @dbUser +

    N'" -Password "' + @dbPassword +

    N'" -BackupDir "' + @backupDir +

    N'" -RetainDays ' + CAST(@retainDays AS nvarchar(20));



IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = @jobName)

BEGIN

    EXEC dbo.sp_delete_job @job_name = @jobName, @delete_unused_schedule = 1;

END

GO



EXEC dbo.sp_add_job

    @job_name = N'EPMS Daily Full Backup',

    @enabled = 1,

    @description = N'Compressed daily full backup for EPMS with cleanup of old .bak files.';

GO



EXEC dbo.sp_add_jobstep

    @job_name = N'EPMS Daily Full Backup',

    @step_name = N'Run Backup Script',

    @subsystem = N'CmdExec',

    @command = @command,

    @retry_attempts = 1,

    @retry_interval = 5;

GO



EXEC dbo.sp_add_schedule

    @schedule_name = @scheduleName,

    @enabled = 1,

    @freq_type = 4,

    @freq_interval = 1,

    @active_start_time = @startTime;

GO



EXEC dbo.sp_attach_schedule

    @job_name = N'EPMS Daily Full Backup',

    @schedule_name = @scheduleName;

GO



EXEC dbo.sp_add_jobserver

    @job_name = N'EPMS Daily Full Backup';

GO



SELECT

    @jobName AS job_name,

    @scheduleName AS schedule_name,

    @dbServer AS db_server,

    @dbName AS db_name,

    @backupDir AS backup_dir,

    @retainDays AS retain_days,

    @startTime AS start_time;

GO

===== END create_epms_daily_backup_job.sql ===== */



PRINT '--- Optional. check_meter_mapping_consistency.sql ---';

GO

/* ===== BEGIN check_meter_mapping_consistency.sql =====

SET NOCOUNT ON;



PRINT '1) AI mapping orphan check';

SELECT 'plc_meter_map' AS src, COUNT(*) AS orphan_cnt

FROM dbo.plc_meter_map pm

LEFT JOIN dbo.meters m ON m.meter_id = pm.meter_id

WHERE m.meter_id IS NULL

UNION ALL

SELECT 'plc_ai_samples', COUNT(*)

FROM dbo.plc_ai_samples s

LEFT JOIN dbo.meters m ON m.meter_id = s.meter_id

WHERE m.meter_id IS NULL

UNION ALL

SELECT 'measurements', COUNT(*)

FROM dbo.measurements x

LEFT JOIN dbo.meters m ON m.meter_id = x.meter_id

WHERE m.meter_id IS NULL

UNION ALL

SELECT 'harmonic_measurements', COUNT(*)

FROM dbo.harmonic_measurements x

LEFT JOIN dbo.meters m ON m.meter_id = x.meter_id

WHERE m.meter_id IS NULL

UNION ALL

SELECT 'flicker_measurements', COUNT(*)

FROM dbo.flicker_measurements x

LEFT JOIN dbo.meters m ON m.meter_id = x.meter_id

WHERE m.meter_id IS NULL;



PRINT '2) Enabled AI map coverage';

SELECT COUNT(*) AS enabled_ai_maps, COUNT(DISTINCT meter_id) AS distinct_meters

FROM dbo.plc_meter_map

WHERE enabled = 1;



SELECT COUNT(*) AS current_meter_count

FROM dbo.meters;



PRINT '3) DI item_name unresolved against meters.name';

WITH meter_names AS (

    SELECT UPPER(LTRIM(RTRIM(name))) AS meter_name

    FROM dbo.meters

    WHERE name IS NOT NULL AND LTRIM(RTRIM(name)) <> ''

),

di_items AS (

    SELECT DISTINCT

        point_id,

        UPPER(LTRIM(RTRIM(ISNULL(item_name, '')))) AS item_name,

        UPPER(LTRIM(RTRIM(ISNULL(panel_name, '')))) AS panel_name

    FROM dbo.plc_di_tag_map

    WHERE enabled = 1

      AND item_name IS NOT NULL

      AND LTRIM(RTRIM(item_name)) <> ''

)

SELECT d.point_id, d.item_name, d.panel_name

FROM di_items d

LEFT JOIN meter_names m ON m.meter_name = d.item_name

WHERE m.meter_name IS NULL

ORDER BY d.item_name, d.panel_name;



PRINT '4) Duplicate panel names in meters';

SELECT UPPER(LTRIM(RTRIM(panel_name))) AS panel_name, COUNT(*) AS meter_count

FROM dbo.meters

WHERE panel_name IS NOT NULL AND LTRIM(RTRIM(panel_name)) <> ''

GROUP BY UPPER(LTRIM(RTRIM(panel_name)))

HAVING COUNT(*) > 1

ORDER BY panel_name;

===== END check_meter_mapping_consistency.sql ===== */



PRINT '--- Optional. check_plc_mapping_master_readiness.sql ---';

GO

/* ===== BEGIN check_plc_mapping_master_readiness.sql =====

/* ---------------------------------------------------------------------------

   PLC Mapping Master Readiness Check



   Purpose

   - Verify whether master tables are complete enough to remove legacy fallback.

   - Compare PLC-level coverage between legacy tables and master tables.



   Recommended use

   1. Run before removing runtime fallback from ModbusConfigRepository.

   2. Confirm every active PLC has AI/DI rows in master tables.

   3. Review token/index duplicates or missing insert mappings.

--------------------------------------------------------------------------- */



PRINT '1) Active PLC coverage by AI master / legacy';

SELECT

    c.plc_id,

    c.enabled,

    ai_master.ai_row_count,

    ai_legacy.ai_row_count AS legacy_ai_row_count,

    CASE

        WHEN ISNULL(ai_master.ai_row_count, 0) > 0 THEN 'READY'

        ELSE 'MISSING_AI_MASTER'

    END AS ai_master_status

FROM dbo.plc_config c

LEFT JOIN (

    SELECT plc_id, COUNT(*) AS ai_row_count

    FROM dbo.plc_ai_mapping_master

    WHERE enabled = 1

    GROUP BY plc_id

) ai_master

    ON ai_master.plc_id = c.plc_id

LEFT JOIN (

    SELECT plc_id, COUNT(*) AS ai_row_count

    FROM dbo.plc_meter_map

    WHERE enabled = 1

    GROUP BY plc_id

) ai_legacy

    ON ai_legacy.plc_id = c.plc_id

WHERE c.enabled = 1

ORDER BY c.plc_id;



PRINT '2) Active PLC coverage by DI master / legacy';

SELECT

    c.plc_id,

    c.enabled,

    di_master.di_row_count,

    di_legacy.di_row_count AS legacy_di_row_count,

    CASE

        WHEN ISNULL(di_master.di_row_count, 0) > 0 THEN 'READY'

        ELSE 'MISSING_DI_MASTER'

    END AS di_master_status

FROM dbo.plc_config c

LEFT JOIN (

    SELECT plc_id, COUNT(*) AS di_row_count

    FROM dbo.plc_di_mapping_master

    WHERE enabled = 1

    GROUP BY plc_id

) di_master

    ON di_master.plc_id = c.plc_id

LEFT JOIN (

    SELECT plc_id, COUNT(*) AS di_row_count

    FROM dbo.plc_di_tag_map

    WHERE enabled = 1

    GROUP BY plc_id

) di_legacy

    ON di_legacy.plc_id = c.plc_id

WHERE c.enabled = 1

ORDER BY c.plc_id;



PRINT '3) AI master rows missing DB insert definition';

SELECT TOP 100

    plc_id,

    meter_id,

    float_index,

    token,

    reg_address,

    measurement_column,

    target_table,

    db_insert_yn,

    note

FROM dbo.plc_ai_mapping_master

WHERE enabled = 1

  AND db_insert_yn = 1

  AND (measurement_column IS NULL OR LTRIM(RTRIM(measurement_column)) = '')

ORDER BY plc_id, meter_id, float_index;



PRINT '4) AI token + float_index duplicates in master';

SELECT

    token,

    float_index,

    COUNT(*) AS dup_count

FROM dbo.plc_ai_mapping_master

WHERE enabled = 1

GROUP BY token, float_index

HAVING COUNT(*) > 1

ORDER BY dup_count DESC, token, float_index;



PRINT '5) DI address duplicates in master';

SELECT

    plc_id,

    di_address,

    bit_no,

    COUNT(*) AS dup_count

FROM dbo.plc_di_mapping_master

WHERE enabled = 1

GROUP BY plc_id, di_address, bit_no

HAVING COUNT(*) > 1

ORDER BY plc_id, di_address, bit_no;



PRINT '6) Final readiness summary';

SELECT

    CASE

        WHEN EXISTS (

            SELECT 1

            FROM dbo.plc_config c

            LEFT JOIN (

                SELECT plc_id, COUNT(*) AS cnt

                FROM dbo.plc_ai_mapping_master

                WHERE enabled = 1

                GROUP BY plc_id

            ) am ON am.plc_id = c.plc_id

            LEFT JOIN (

                SELECT plc_id, COUNT(*) AS cnt

                FROM dbo.plc_di_mapping_master

                WHERE enabled = 1

                GROUP BY plc_id

            ) dm ON dm.plc_id = c.plc_id

            WHERE c.enabled = 1

              AND (ISNULL(am.cnt, 0) = 0 OR ISNULL(dm.cnt, 0) = 0)

        ) THEN 'NOT_READY'

        ELSE 'READY_FOR_FALLBACK_REVIEW'

    END AS fallback_removal_status;

===== END check_plc_mapping_master_readiness.sql ===== */



PRINT '--- Optional. check_peak_management_readiness.sql ---';

GO

/* ===== BEGIN check_peak_management_readiness.sql =====

SET NOCOUNT ON;



PRINT '=== EPMS Peak Management Readiness Check ===';



DECLARE @now DATETIME2 = SYSDATETIME();



SELECT

    @now AS checked_at,

    DB_NAME() AS database_name;



PRINT '--- 1. Core object existence ---';



SELECT

    'dbo.peak_policy_master' AS object_name,

    CASE WHEN OBJECT_ID('dbo.peak_policy_master', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END AS status

UNION ALL

SELECT

    'dbo.peak_policy_store_map',

    CASE WHEN OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END

UNION ALL

SELECT

    'dbo.peak_15min_summary',

    CASE WHEN OBJECT_ID('dbo.peak_15min_summary', 'U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END

UNION ALL

SELECT

    'dbo.sp_refresh_peak_15min_summary',

    CASE WHEN OBJECT_ID('dbo.sp_refresh_peak_15min_summary', 'P') IS NOT NULL THEN 'OK' ELSE 'MISSING' END;



PRINT '--- 2. SQL Server Agent job existence ---';



IF DB_ID('msdb') IS NOT NULL

BEGIN

    SELECT

        j.name AS job_name,

        CASE WHEN j.enabled = 1 THEN 'ENABLED' ELSE 'DISABLED' END AS job_status

    FROM msdb.dbo.sysjobs AS j

    WHERE j.name = 'EPMS Peak 15min Summary Refresh';



    IF NOT EXISTS (

        SELECT 1

        FROM msdb.dbo.sysjobs

        WHERE name = 'EPMS Peak 15min Summary Refresh'

    )

    BEGIN

        SELECT

            'EPMS Peak 15min Summary Refresh' AS job_name,

            'MISSING' AS job_status;

    END

END

ELSE

BEGIN

    SELECT

        'msdb' AS dependency_name,

        'UNAVAILABLE' AS status;

END;



PRINT '--- 3. Recent measurements status ---';



SELECT

    MAX(m.measured_at) AS latest_measured_at,

    COUNT_BIG(*) AS measurement_row_count

FROM dbo.measurements AS m;



SELECT TOP 10

    m.meter_id,

    MAX(m.measured_at) AS latest_measured_at,

    COUNT_BIG(*) AS row_count_last_24h

FROM dbo.measurements AS m

WHERE m.measured_at >= DATEADD(HOUR, -24, @now)

GROUP BY m.meter_id

ORDER BY latest_measured_at DESC;



PRINT '--- 4. Peak policy status ---';



IF OBJECT_ID('dbo.peak_policy_master', 'U') IS NOT NULL

AND OBJECT_ID('dbo.peak_policy_store_map', 'U') IS NOT NULL

BEGIN

    SELECT

        COUNT(*) AS policy_count,

        SUM(CASE WHEN p.effective_to IS NULL OR p.effective_to >= CAST(@now AS DATE) THEN 1 ELSE 0 END) AS active_or_open_ended_policy_count

    FROM dbo.peak_policy_master AS p;



    SELECT TOP 20

        p.policy_id,

        p.policy_name,

        p.peak_limit_kw,

        p.warning_threshold_pct,

        p.control_threshold_pct,

        p.priority_level,

        p.control_enabled,

        p.effective_from,

        p.effective_to,

        COUNT(m.store_id) AS assigned_store_count

    FROM dbo.peak_policy_master AS p

    LEFT JOIN dbo.peak_policy_store_map AS m

        ON m.policy_id = p.policy_id

    GROUP BY p.policy_id, p.policy_name, p.peak_limit_kw, p.warning_threshold_pct, p.control_threshold_pct,

             p.priority_level, p.control_enabled, p.effective_from, p.effective_to

    ORDER BY p.priority_level ASC, p.policy_id ASC;

END

ELSE

BEGIN

    SELECT

        'dbo.peak_policy_master / dbo.peak_policy_store_map' AS object_name,

        'SKIPPED' AS status;

END;



PRINT '--- 5. 15-minute summary status ---';



IF OBJECT_ID('dbo.peak_15min_summary', 'U') IS NOT NULL

BEGIN

    SELECT

        COUNT(*) AS summary_row_count,

        MAX(bucket_start) AS latest_bucket_start,

        MAX(refreshed_at) AS latest_refreshed_at,

        DATEDIFF(MINUTE, MAX(refreshed_at), @now) AS refresh_lag_minutes

    FROM dbo.peak_15min_summary;



    SELECT TOP 20

        meter_id,

        bucket_start,

        avg_active_power_total,

        refreshed_at

    FROM dbo.peak_15min_summary

    ORDER BY refreshed_at DESC, bucket_start DESC;

END

ELSE

BEGIN

    SELECT

        'dbo.peak_15min_summary' AS object_name,

        'SKIPPED' AS status;

END;



PRINT '--- 6. Tenant-to-meter mapping health ---';



IF OBJECT_ID('dbo.tenant_meter_map', 'U') IS NOT NULL

AND OBJECT_ID('dbo.tenant_store', 'U') IS NOT NULL

BEGIN

    SELECT

        COUNT(*) AS total_mapping_count,

        SUM(CASE WHEN valid_to IS NULL OR valid_to >= CAST(@now AS DATE) THEN 1 ELSE 0 END) AS active_mapping_count

    FROM dbo.tenant_meter_map;



    SELECT TOP 20

        s.store_id,

        s.store_name,

        COUNT(tm.map_id) AS active_mapping_count

    FROM dbo.tenant_store AS s

    LEFT JOIN dbo.tenant_meter_map AS tm

        ON tm.store_id = s.store_id

       AND tm.valid_from <= CAST(@now AS DATE)

       AND (tm.valid_to IS NULL OR tm.valid_to >= CAST(@now AS DATE))

    GROUP BY s.store_id, s.store_name

    HAVING COUNT(tm.map_id) = 0

    ORDER BY s.store_id;

END

ELSE

BEGIN

    SELECT

        'tenant_store / tenant_meter_map' AS object_name,

        'SKIPPED' AS status;

END;



PRINT '=== End of readiness check ===';

===== END check_peak_management_readiness.sql ===== */



*/



PRINT '=== EPMS SQL All-In-One Runner: end ===';

GO
