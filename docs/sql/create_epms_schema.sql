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

/****** Object:  Table [dbo].[alarm_log]    Script Date: 2026-04-02 오후 1:00:03 ******/
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
/****** Object:  Index [idx_alarm_meter_time]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_alarm_meter_time] ON [dbo].[alarm_log]
(
	[meter_id] ASC,
	[triggered_at] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
SET ANSI_PADDING ON

/****** Object:  Index [idx_alarm_severity]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_alarm_severity] ON [dbo].[alarm_log]
(
	[severity] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[alarm_rule]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Index [ux_alarm_rule_code]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Table [dbo].[building_alias]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Index [UX_building_alias_keyword]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_building_alias_keyword] ON [dbo].[building_alias]
(
	[alias_keyword] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
ALTER TABLE [dbo].[building_alias] ADD  CONSTRAINT [DF_building_alias_is_active]  DEFAULT ((1)) FOR [is_active]
ALTER TABLE [dbo].[building_alias] ADD  CONSTRAINT [DF_building_alias_created_at]  DEFAULT (sysdatetime()) FOR [created_at]
ALTER TABLE [dbo].[building_alias] ADD  CONSTRAINT [DF_building_alias_updated_at]  DEFAULT (sysdatetime()) FOR [updated_at]
GO

/****** Object:  Table [dbo].[daily_measurements]    Script Date: 2026-04-02 오후 1:00:03 ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[daily_measurements](
	[day_id] [bigint] IDENTITY(1,1) NOT NULL,
	[meter_id] [int] NULL,
	[measured_date] [date] NOT NULL,
	[avg_voltage] [float] NULL,
	[avg_current] [float] NULL,
	[avg_power_factor] [float] NULL,
	[max_voltage] [float] NULL,
	[min_voltage] [float] NULL,
	[max_current] [float] NULL,
	[min_current] [float] NULL,
	[energy_consumed_kwh] [float] NULL,
	[energy_generated_kwh] [float] NULL,
	[voltage_unbalance_rate] [float] NULL,
	[harmonic_distortion_rate] [float] NULL,
PRIMARY KEY CLUSTERED 
(
	[day_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

/****** Object:  Index [idx_daily_meter_date]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE UNIQUE NONCLUSTERED INDEX [idx_daily_meter_date] ON [dbo].[daily_measurements]
(
	[meter_id] ASC,
	[measured_date] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[device_events]    Script Date: 2026-04-02 오후 1:00:03 ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET ANSI_PADDING ON
CREATE TABLE [dbo].[device_events](
	[event_id] [bigint] IDENTITY(1,1) NOT NULL,
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
/****** Object:  Index [idx_device_event_time]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_device_event_time] ON [dbo].[device_events]
(
	[device_id] ASC,
	[event_time] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
SET ANSI_PADDING ON

/****** Object:  Index [idx_device_event_type]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_device_event_type] ON [dbo].[device_events]
(
	[event_type] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
ALTER TABLE [dbo].[device_events] ADD  DEFAULT ((0)) FOR [trip_count]
ALTER TABLE [dbo].[device_events] ADD  DEFAULT ((0)) FOR [outage_count]
ALTER TABLE [dbo].[device_events] ADD  DEFAULT ((0)) FOR [switch_count]
GO

/****** Object:  Table [dbo].[devices]    Script Date: 2026-04-02 오후 1:00:03 ******/
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
/****** Object:  Index [idx_devices_id]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE UNIQUE NONCLUSTERED INDEX [idx_devices_id] ON [dbo].[devices]
(
	[device_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
SET ANSI_PADDING ON

/****** Object:  Index [idx_devices_location]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_devices_location] ON [dbo].[devices]
(
	[location] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
ALTER TABLE [dbo].[devices] ADD  DEFAULT ('Active') FOR [status]
GO

/****** Object:  Table [dbo].[di_group_rule_map]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Index [ux_di_group_rule_map_metric]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE UNIQUE NONCLUSTERED INDEX [ux_di_group_rule_map_metric] ON [dbo].[di_group_rule_map]
(
	[metric_key] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT ('ANY_ON') FOR [match_mode]
ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT ((1)) FOR [enabled]
ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT (sysutcdatetime()) FOR [created_at]
ALTER TABLE [dbo].[di_group_rule_map] ADD  DEFAULT (sysutcdatetime()) FOR [updated_at]
GO

/****** Object:  Table [dbo].[di_signal_group_map]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Index [ux_di_signal_group_map_key]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Table [dbo].[flicker_measurements]    Script Date: 2026-04-02 오후 1:00:03 ******/
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

/****** Object:  Index [idx_flicker_measured_at]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_flicker_measured_at] ON [dbo].[flicker_measurements]
(
	[measured_at] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
/****** Object:  Index [idx_flicker_meter_id]    Script Date: 2026-04-02 오후 1:00:03 ******/
CREATE NONCLUSTERED INDEX [idx_flicker_meter_id] ON [dbo].[flicker_measurements]
(
	[meter_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[harmonic_measurements]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Table [dbo].[measurements]    Script Date: 2026-04-02 오후 1:00:04 ******/
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
/****** Object:  Index [idx_measurements_id]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE UNIQUE NONCLUSTERED INDEX [idx_measurements_id] ON [dbo].[measurements]
(
	[measurement_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
/****** Object:  Index [idx_measurements_meter_time]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE NONCLUSTERED INDEX [idx_measurements_meter_time] ON [dbo].[measurements]
(
	[meter_id] ASC,
	[measured_at] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[measurenets]    Script Date: 2026-04-02 오후 1:00:04 ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET ANSI_PADDING ON
CREATE TABLE [dbo].[measurenets](
	[plc_id] [int] IDENTITY(1,1) NOT NULL,
	[plc_name] [nvarchar](100) COLLATE Korean_Wansung_CI_AS NOT NULL,
	[protocol] [nvarchar](30) COLLATE Korean_Wansung_CI_AS NOT NULL,
	[ip_address] [varchar](45) COLLATE Korean_Wansung_CI_AS NOT NULL,
	[port] [int] NOT NULL,
	[is_active] [bit] NOT NULL,
	[created_at] [datetime2](7) NOT NULL,
	[updated_at] [datetime2](7) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[plc_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_measurenets_ip_port] UNIQUE NONCLUSTERED 
(
	[ip_address] ASC,
	[port] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

SET ANSI_PADDING OFF
ALTER TABLE [dbo].[measurenets] ADD  CONSTRAINT [DF_measurenets_protocol]  DEFAULT ('MODBUS_TCP') FOR [protocol]
ALTER TABLE [dbo].[measurenets] ADD  CONSTRAINT [DF_measurenets_active]  DEFAULT ((1)) FOR [is_active]
ALTER TABLE [dbo].[measurenets] ADD  CONSTRAINT [DF_measurenets_created]  DEFAULT (sysutcdatetime()) FOR [created_at]
ALTER TABLE [dbo].[measurenets] ADD  CONSTRAINT [DF_measurenets_updated]  DEFAULT (sysutcdatetime()) FOR [updated_at]
GO

/****** Object:  Table [dbo].[meter_tree]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Index [IX_meter_tree_child]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE NONCLUSTERED INDEX [IX_meter_tree_child] ON [dbo].[meter_tree]
(
	[child_meter_id] ASC,
	[is_active] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
/****** Object:  Index [IX_meter_tree_parent]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Table [dbo].[meters]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Index [idx_meters_building_usage]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE NONCLUSTERED INDEX [idx_meters_building_usage] ON [dbo].[meters]
(
	[building_name] ASC,
	[usage_type] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
/****** Object:  Index [idx_meters_meter_id]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE UNIQUE NONCLUSTERED INDEX [idx_meters_meter_id] ON [dbo].[meters]
(
	[meter_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[metric_catalog]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Table [dbo].[metric_catalog_tag_map]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Index [ix_metric_catalog_tag_map_metric_key]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE NONCLUSTERED INDEX [ix_metric_catalog_tag_map_metric_key] ON [dbo].[metric_catalog_tag_map]
(
	[metric_key] ASC,
	[enabled] ASC,
	[sort_no] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
SET ANSI_PADDING ON

/****** Object:  Index [ux_metric_catalog_tag_map_key_token]    Script Date: 2026-04-02 오후 1:00:04 ******/
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

/****** Object:  Table [dbo].[monthly_measurements]    Script Date: 2026-04-02 오후 1:00:04 ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[monthly_measurements](
	[month_id] [bigint] IDENTITY(1,1) NOT NULL,
	[meter_id] [int] NULL,
	[measured_month] [date] NOT NULL,
	[avg_voltage] [float] NULL,
	[avg_current] [float] NULL,
	[avg_power_factor] [float] NULL,
	[max_voltage] [float] NULL,
	[min_voltage] [float] NULL,
	[energy_consumed_kwh] [float] NULL,
	[energy_generated_kwh] [float] NULL,
	[voltage_unbalance_rate] [float] NULL,
	[harmonic_distortion_rate] [float] NULL,
PRIMARY KEY CLUSTERED 
(
	[month_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

/****** Object:  Index [idx_monthly_meter_month]    Script Date: 2026-04-02 오후 1:00:04 ******/
CREATE UNIQUE NONCLUSTERED INDEX [idx_monthly_meter_month] ON [dbo].[monthly_measurements]
(
	[meter_id] ASC,
	[measured_month] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[plc_ai_measurements_match]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_ai_samples]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_ai_write_task]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_config]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_di_map]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_di_samples]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_di_tag_map]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_meter_map]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_metric_random_range]    Script Date: 2026-04-02 오후 1:00:05 ******/
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

/****** Object:  Table [dbo].[plc_write_control]    Script Date: 2026-04-02 오후 1:00:06 ******/
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

/****** Object:  Table [dbo].[usage_type_alias]    Script Date: 2026-04-02 오후 1:00:06 ******/
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

/****** Object:  Index [UX_usage_type_alias_keyword]    Script Date: 2026-04-02 오후 1:00:06 ******/
CREATE UNIQUE NONCLUSTERED INDEX [UX_usage_type_alias_keyword] ON [dbo].[usage_type_alias]
(
	[alias_keyword] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
ALTER TABLE [dbo].[usage_type_alias] ADD  CONSTRAINT [DF_usage_type_alias_is_active]  DEFAULT ((1)) FOR [is_active]
ALTER TABLE [dbo].[usage_type_alias] ADD  CONSTRAINT [DF_usage_type_alias_created_at]  DEFAULT (sysdatetime()) FOR [created_at]
ALTER TABLE [dbo].[usage_type_alias] ADD  CONSTRAINT [DF_usage_type_alias_updated_at]  DEFAULT (sysdatetime()) FOR [updated_at]
GO

/****** Object:  Table [dbo].[voltage_events]    Script Date: 2026-04-02 오후 1:00:06 ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
SET ANSI_PADDING ON
CREATE TABLE [dbo].[voltage_events](
	[event_id] [bigint] IDENTITY(1,1) NOT NULL,
	[meter_id] [int] NULL,
	[event_type] [varchar](10) COLLATE Korean_Wansung_CI_AS NULL,
	[triggered_at] [datetime] NULL,
	[duration_ms] [int] NULL,
	[voltage_level] [float] NULL,
	[severity] [varchar](20) COLLATE Korean_Wansung_CI_AS NULL,
	[description] [text] COLLATE Korean_Wansung_CI_AS NULL,
PRIMARY KEY CLUSTERED 
(
	[event_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

SET ANSI_PADDING OFF
/****** Object:  Index [idx_voltage_meter_time]    Script Date: 2026-04-02 오후 1:00:06 ******/
CREATE NONCLUSTERED INDEX [idx_voltage_meter_time] ON [dbo].[voltage_events]
(
	[meter_id] ASC,
	[triggered_at] DESC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
SET ANSI_PADDING ON

/****** Object:  Index [idx_voltage_type]    Script Date: 2026-04-02 오후 1:00:06 ******/
CREATE NONCLUSTERED INDEX [idx_voltage_type] ON [dbo].[voltage_events]
(
	[event_type] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
GO

/****** Object:  Table [dbo].[yearly_measurements]    Script Date: 2026-04-02 오후 1:00:06 ******/
SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
CREATE TABLE [dbo].[yearly_measurements](
	[year_id] [bigint] IDENTITY(1,1) NOT NULL,
	[meter_id] [int] NULL,
	[measured_year] [int] NOT NULL,
	[avg_voltage] [float] NULL,
	[avg_current] [float] NULL,
	[avg_power_factor] [float] NULL,
	[max_voltage] [float] NULL,
	[min_voltage] [float] NULL,
	[energy_consumed_kwh] [float] NULL,
	[energy_generated_kwh] [float] NULL,
	[voltage_unbalance_rate] [float] NULL,
	[harmonic_distortion_rate] [float] NULL,
PRIMARY KEY CLUSTERED 
(
	[year_id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

/****** Object:  Index [idx_yearly_meter_year]    Script Date: 2026-04-02 오후 1:00:06 ******/
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

ALTER TABLE [dbo].[voltage_events]  WITH CHECK ADD FOREIGN KEY([meter_id])
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
    b.device_id,
    b.device_name,
    b.location,
    b.panel_name,
    b.building_name,
    b.install_date,
	b.status,
	b.remarks,

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
FROM devices b
INNER JOIN device_events e ON b.device_id = e.device_id;
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

    -- 전압
    ms.voltage_ab, ms.voltage_bc, ms.voltage_ca,
    ms.voltage_an, ms.voltage_bn, ms.voltage_cn,

    -- 전류
    ms.current_a, ms.current_b, ms.current_c, ms.current_n,

    -- 평균값
    ms.average_voltage,
    ms.average_current,

    -- 역률 및 주파수
    ms.frequency,
    ms.power_factor,
    ms.power_factor_a, ms.power_factor_b, ms.power_factor_c,

    -- 전력
    ms.active_power_total,
    ms.reactive_power_total,
    ms.apparent_power_total,
    ms.max_power,

    -- 에너지
    ms.energy_consumed_total,
    ms.energy_generated_total,

    -- 전략량
    ms.voltage_max,
    ms.voltage_min,
    ms.voltage_stddev,
    ms.voltage_variation_rate,
    ms.energy_generated_delta,

    -- 품질 지표
    ms.voltage_unbalance_rate,
    ms.harmonic_distortion_rate,
    ms.quality_status,
    -- 위상각
    ms.voltage_phase_a, ms.voltage_phase_b, ms.voltage_phase_c,
    ms.current_phase_a, ms.current_phase_b, ms. current_phase_c

FROM meters m
INNER JOIN measurements ms ON m.meter_id = ms.meter_id;
GO

IF OBJECT_ID(N'[dbo].[vw_voltage_event_log]', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_voltage_event_log];
GO
CREATE VIEW vw_voltage_event_log AS
SELECT
    m.meter_id,
    m.name AS meter_name,
    m.panel_name,
    m.building_name,
    m.usage_type,

    ve.event_id,
    ve.event_type,              -- 'sag' or 'swell'
    ve.triggered_at,
    ve.duration_ms,
    ve.voltage_level,
    ve.severity,
    ve.description
FROM meters m
INNER JOIN voltage_events ve ON m.meter_id = ve.meter_id;
GO

