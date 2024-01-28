# BARF
Because of ARkansas Failure (BARF) is made to help you produce your Clever files so you can continue to roster students during the great January 2024 Cognos Outage. This is NOT a 1:1 file clone of the files produced by Cognos/Clever project. You should review them before uploading them to Clever.

## Caution
These download defintions are based on the eSchool tables and are not filtered down. They include sensitive information you may otherwise not store locally. You should securely scrub and delete the local database once you've uploaded the required data.

## Requirements
- You must already have the eSchoolModule installed and configured.
- You must have READ permissions to nearly all of eSchool.
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