# BARF
Because of ARkansas Failure (BARF) is made to help you produce your Clever files so you can continue to roster students during the great January 2024 Cognos Outage. This is NOT a 1:1 file clone of the files produced by Cognos/Clever project. You should review them before uploading them to Clever.

Realizing that making this project was necessary made me want to BARF.

Don't expect this to be fast. eSchool Download Definitions are stupid slow.

These scripts come without warranty of any kind. Use them at your own risk. We assume no liability for the accuracy, correctness, completeness, or usefulness of any information provided by this site nor for any sort of damages using these scripts may cause.

## Caution
These download defintions are based on the eSchool tables and are not filtered down. They include sensitive information you may otherwise not store locally. You should securely scrub and delete the local database once you've uploaded the required data.

## Requirements
- Powershell 7.4+
- SimplySQL 1.9.1+ Powershell Module (Install-Module SimplySQL or Update-Module SimplySQL -Force)
- csvkit, Requires Python then run "pip install csvkit"
- You must already have the eSchoolModule installed and configured. (https://github.com/AR-k12code/eSchoolModule)
- You must have READ permissions to nearly all of eSchool. (Please use roles!)
- You need WRITE permissions to Create Upload/Download Definitions.
- You need to be able to run Upload/Download Definitions.

## Example
Open Powershell and Run:
````
.\barf.ps1
````

## Files Produced:
- students.csv
- teachers.csv
- schools.csv
- enrollments.csv
- sections.csv

## Upload to Clever
You can find your SFTP credentials here: https://schools.clever.com/sync/settings