
# as_marcao

An ArchivesSpace plugin for exporting Archival Objects as MARC XML for selected
Resources on a schedule.

This plugin was developed against ArchivesSpace v3.2, but it should be fine on
any recent version.

Developed by Hudson Molonglo for Princeton University.

## Overview

The plugin is designed to run under a schedule, specified in configuration (see
below).

Each run will export all of the Archival Objects, modified since the last run,
belonging to all Resources that have a flag set (a User Defined Boolean field)
in one MARC XML file. The top level tag will be a &lt;collection&gt; tag, then
each AO will be a &lt;record&gt; tag within it.

The MARC XML is exported to a file called `marcao/marcao_export.xml` in
ArchivesSpace's shared data area. Another file is generated called
`marcao/report.json`. This contains metadata about the last export run -- the
one that produced the export file.

Then the export file is uploaded via SFTP using the specified configuration.
The SFTP upload will be retried up to 10 times at 30 second intervals to
allow for transient network issues.

Each export run will only export AOs that have been modified since the last
export. To force a full export, remove the `report.json` file.

Information about the last export and configuration can be viewed by system
administrators in the ArchivesSpace Staff interface.
```
  System > MARC AO Report
```


## Installation

The plugin has no other special installation requirements.
No template overrides.
No database migrations.

## Configuration

Sample configuration:
```
  AppConfig[:marcao_schedule] = '22 2 * * *'
  AppConfig[:marcao_flag_field] = 'boolean_1'
  AppConfig[:marcao_sftp_host] = '127.0.0.1'
  AppConfig[:marcao_sftp_user] = 'a_user'
  AppConfig[:marcao_sftp_password] = 'secret password'
  AppConfig[:marcao_sftp_path] = '/remote/path'
  AppConfig[:marcao_sftp_timeout] = 30
```

### marcao_schedule
A cron string that defines when the export will run.
The example says to run at 2:22AM every day.

### marcao_flag_field
The name of the User Defined Boolean field to check to see if a Resource
should be included in the export.
Valid values: `boolean_1`, `boolean_2`, `boolean_3`

### marcao_sftp_host
The hostname or IP address of the SFTP server to upload to.

### marcao_sftp_user
The username to authenticate with on the SFTP server.

### marcao_sftp_password
The password to authenticate with on the SFTP server.

### marcao_sftp_path
The path on the SFTP server to upload the exported records to.

### marcao_sftp_timeout
Timeout in seconds to use when connecting to the SFTP server (default 30).


## Report

When the exporter runs it generates a report about the run. The report can be
accessed by system administrators in the Staff interface
(`System > MARC AO Report`), and via a backend endpoint
(`GET /marcao/last_report`).

The report has the following information:

  - `status`
      - The status of the exporter run. See below for an explanation of possible
        values.
  - `error`
      - Any error message generated by the run. This field is only included if
        there was an error.
  - `last_success_at`
      - The date and time that the last successful export run started. This
        value is used by the exporter to determine the cut off for modified
        Archival Objects.
  - `export_started_at`
      - The date and time that the export run started.
  - `export_completed_at`
      - The date and time that the export run completed.
  - `export_file`
      - The absolute file path of the exported file. 
  - `resource_ids_selected`
      - The list of Resource IDs that were included in the export.
  - `archival_objects_exported`
      - The number of Archival Objects that were exported.

The status can have the following values:

  - `export_fail`
      - The MARC XML export failed. The error message will be included in the
        report.
  - `sftp_fail`
      - The export succeeded, but the SFTP upload failed. The error message will
        be included in the report.
  - `no_sftp`
      - The export succeeded, but SFTP was not configured.
  - `ok`
      - The export and SFTP upload succeeded. All is well.


## Backend Endpoints

The plugin provides backend endpoints that allow for running marcao manually.
Only system administrators have permission to access these endpoints.

```
  GET /marcao/export
  GET /marcao/last_report
  GET /repositories/:repo_id/archival_objects/:id/marcao
  GET /repositories/:repo_id/resources/:id/marcao
```

### /marcao/export
Run the export. This runs the whole export process, including the SFTP upload,
just as though it had run under the scheduler.

### /marcao/last_report
Returns the report of the last export as JSON.

### /repositories/:repo_id/archival_objects/:id/marcao
Returns the MARC XML for the Archival Object. The XML returned is just the
&lt;record&gt; tag, ie. not wrapped in a &lt;collection&gt; tag.

### /repositories/:repo_id/resources/:id/marcao
Returns the MARC XML for the Archival Objects under the Resource.
It accepts an optional `since` parameter that specifies a Datetime.
Only AOs modified since that Datetime will be included.
Examples: `since=2023-03-01`, `since=2023-03-01T12:00:00`
