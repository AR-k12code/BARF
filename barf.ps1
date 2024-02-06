#Requires -Version 7.4
#Requires -Modules eSchoolModule,SimplySql
<#

.SYNOPSIS
Because of ARkansas Failure (BARF) we will pull data directly from eSchool to build the Clever Files.

.DESCRIPTION
Desperate times call for desparate measures.

#>

#We need to work on schedules.
$schoolyear = (Get-Date).Month -ge 7 ? (Get-Date).Year + 1 : (Get-Date).Year

try {
    Connect-ToeSchool
} catch {
    Write-Error "Unable to connect to eSchool. Please check your credentials." -ErrorAction Stop
}

Open-SQLiteConnection -DataSource "$PSScriptRoot\db.sqlite3" -ErrorAction Stop

if (-Not(Test-Path "$HOME\.config\eSchoolModule\eSchoolDatabase.csv")) {
    Get-eSPDefinitionsUpdates
}

function Remove-StringLatinCharacter {
    <#
.SYNOPSIS
    Function to remove diacritics from a string
.DESCRIPTION
    Function to remove diacritics from a string
.PARAMETER String
    Specifies the String that will be processed
.EXAMPLE
    Remove-StringLatinCharacter -String "L'été de Raphaël"
    L'ete de Raphael
.EXAMPLE
    Foreach ($file in (Get-ChildItem c:\test\*.txt))
    {
        # Get the content of the current file and remove the diacritics
        $NewContent = Get-content $file | Remove-StringLatinCharacter
        # Overwrite the current file with the new content
        $NewContent | Set-Content $file
    }
    Remove diacritics from multiple files
.NOTES
    Francois-Xavier Cat
    lazywinadmin.com
    @lazywinadmin
    github.com/lazywinadmin
    BLOG ARTICLE
        https://lazywinadmin.com/2015/05/powershell-remove-diacritics-accents.html
    VERSION HISTORY
        1.0.0.0 | Francois-Xavier Cat
            Initial version Based on Marcin Krzanowic code
        1.0.0.1 | Francois-Xavier Cat
            Added support for ValueFromPipeline
        1.0.0.2 | Francois-Xavier Cat
            Add Support for multiple String
            Add Error Handling
    .LINK
        https://github.com/lazywinadmin/PowerShell
#>
    [CmdletBinding()]
    PARAM (
        [Parameter(ValueFromPipeline = $true)]
        [System.String[]]$String
    )
    PROCESS {
        FOREACH ($StringValue in $String) {
            Write-Verbose -Message "$StringValue"

            TRY {
                [Text.Encoding]::ASCII.GetString([Text.Encoding]::GetEncoding("Cyrillic").GetBytes($StringValue))
            }
            CATCH {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }
    }
}

$downloadDefinitions = Invoke-eSPExecuteSearch -SearchType UPLOADDEF

#This intentionally does not contain REG_CONTACT or REG_STU_CONTACT.
$tables = @(
    "reg_building",
    "reg_calendar",
    "reg_mp_dates",
    "reg_staff",
    "reg_staff_bldgs",
    "schd_course",
    "schd_ms",
    "schd_ms_mp",
    "schd_ms_session",
    "schd_ms_staff",
    "regtb_ethnicity",
    "regtb_language",
    "reg_entry_with"
)

#BARF1 is tables that can be filtered to active students with additional SQL.
if ($downloadDefinitions.interface_id -notcontains "BARF1") {
    New-eSPBulkDownloadDefinition `
        -Tables @('reg','reg_academic','reg_stu_contact','reg_personal','schd_stu_conf_mp','schd_stu_course','schd_stu_crs_dates','reg_ethnicity') `
        -InterfaceId BARF1 `
        -AdditionalSQL "WHERE STUDENT_ID IN (SELECT STUDENT_ID FROM REG WHERE CURRENT_STATUS = 'A')" `
        -Delimiter '|' `
        -Description "Because of ARkansas Failure" `
        -FilePrefix "barf-"

    Connect-ToeSchool #we have to reauthenticate to run new definitions.
}

#BARF2 is REG_CONTACT to filter to only active contacts.
if ($downloadDefinitions.interface_id -notcontains "BARF2") {
    New-eSPBulkDownloadDefinition `
        -Tables @('reg_contact','reg_contact_phone') `
        -InterfaceId BARF2 `
        -AdditionalSQL "WHERE CONTACT_ID IN (SELECT CONTACT_ID FROM REG_STU_CONTACT WHERE STUDENT_ID IN (SELECT STUDENT_ID FROM REG WHERE CURRENT_STATUS = 'A'))" `
        -Delimiter '|' `
        -Description "Because of ARkansas Failure 2" `
        -FilePrefix "barf-"

    Connect-ToeSchool #we have to reauthenticate to run new definitions.
}

#BARF3 is schedule/roster/staff information. This should be filtered down to SCHOOL_YEAR if it exists on the table.
if ($downloadDefinitions.interface_id -notcontains "BARF3") {
    New-eSPBulkDownloadDefinition `
        -Tables $tables `
        -InterfaceId BARF3 `
        -Delimiter '|' `
        -Description "Because of ARkansas Failure 3" `
        -FilePrefix "barf-"

    Connect-ToeSchool #we have to reauthenticate to run new definitions.
}

Get-Date
#We can't wait on any of these because we can't predict when it will be done.
Invoke-eSPDownloadDefinition -InterfaceID BARF1 #-Wait
Invoke-eSPDownloadDefinition -InterfaceID BARF2 #-Wait
Invoke-eSPDownloadDefinition -InterfaceID BARF3 -Wait #we have to wait on at least one of them. But we have to check later to make sure that all tasks are complete.

#wait until all tasks are complete.
do {
    $taskCount = (Get-eSPTaskList -ActiveTasksOnly | Where-Object -Property TaskName -LIKE "BARF*").Count
    Write-Host "Waiting on $taskCount tasks to complete."
    Start-Sleep -Seconds 10
} until ($taskCount -eq 0)

Get-Date

#Now we need to download the files.
$tables +
    @('reg','reg_academic','reg_stu_contact','reg_personal','schd_stu_conf_mp','schd_stu_course','schd_stu_crs_dates','reg_ethnicity') +
    @('reg_contact','reg_contact_phone') |
        ForEach-Object {

            #Because of carriage return and line feed we need to replace them with something else so the CSV can import correctly. We also need to run it through Remove-StringLatinCharacter to remove any non-ASCII characters.
            $data = (Get-eSPFile -FileName "barf-$($PSItem).csv" -Raw) -replace "`r",'--CR--' -replace "`n",'--LF--' -replace '#!#--CR----LF--',"#!#`r`n" | Remove-StringLatinCharacter
            
            if ($data -match '#!#') {

                #the dates in reg_mp_dates need to be updated to MM/dd/yyyy for backwards compatibility.
                if ($PSItem -eq "reg_mp_dates") {
                    $reg_mp_dates = $data | ConvertFrom-Csv -Delimiter '|'
                    $reg_mp_dates | ForEach-Object {
                        $PSItem.START_DATE = [datetime]$PSItem.START_DATE | Get-Date -Format "MM/dd/yyyy"
                        $PSItem.END_DATE = [datetime]$PSItem.END_DATE | Get-Date -Format "MM/dd/yyyy"
                    }
                    $reg_mp_dates | Export-Csv -Path "$($PSScriptRoot)\files\$($PSItem).csv" -Delimiter '|' -NoTypeInformation -Force -Verbose -UseQuotes AsNeeded
                } else {
                    $data | Out-File -Path "$($PSScriptRoot)\files\$($PSItem).csv" -Force -NoNewline -Verbose
                }

            } else {
                Write-Error "File does not contain line termination characters." -ErrorAction Stop
            }
        }

$tables +
    @('reg','reg_academic','reg_stu_contact','reg_personal','schd_stu_conf_mp','schd_stu_course','schd_stu_crs_dates','reg_ethnicity') +
    @('reg_contact','reg_contact_phone') |
        ForEach-Object {

            #Now we need to import the data into the database.
            Write-Output "Importing $PSItem to table barf_import_$($PSItem)_csv"
            & csvsql -I --db "sqlite:///db.sqlite3" -d '|' -y 0 --insert --overwrite --blanks --tables "barf_import_$($PSItem)_csv" "$PSScriptRoot\files\$($PSItem).csv"
        
        }

#Primary phone number based on Contact_ID
Invoke-SqlUpdate -Query "CREATE TEMP TABLE IF NOT EXISTS contacts_phonenumber AS
    SELECT
        CONTACT_ID
        ,PHONE_TYPE
        ,PHONE
    FROM (SELECT *,
        MIN(CASE PHONE_TYPE
            WHEN 'C' THEN 1
            WHEN 'C1' THEN 2
            WHEN 'C2' THEN 3
            WHEN 'M' THEN 4
            WHEN 'CO' THEN 5
            WHEN 'H' THEN 6
            WHEN 'H1' THEN 7
            WHEN 'H2' THEN 8
            WHEN 'A' THEN 9
            WHEN 'A1' THEN 10
            ELSE 99
        END) AS Priority
        FROM barf_import_reg_contact_phone_csv
        WHERE PHONE_TYPE NOT IN ('W','W1','W2') /*We never want work numbers here.*/
        GROUP BY Contact_id)"

#Students Table - We do not have to exclude grades here.
Invoke-SqlQuery -Query "SELECT
        barf_import_reg_csv.BUILDING AS School_id
        ,barf_import_reg_csv.STUDENT_ID AS Student_id
        ,barf_import_reg_csv.STUDENT_ID AS Student_number
        ,barf_import_reg_personal_csv.STATE_REPORT_ID AS State_id
        ,barf_import_reg_csv.LAST_NAME AS Last_name
        ,barf_import_reg_csv.MIDDLE_NAME AS Middle_name
        ,barf_import_reg_csv.FIRST_NAME AS First_name
        ,CASE barf_import_reg_csv.GRADE
            WHEN 'KF' THEN 'K'
            WHEN '01' THEN '1'
            WHEN '02' THEN '2'
            WHEN '03' THEN '3'
            WHEN '04' THEN '4'
            WHEN '05' THEN '5'
            WHEN '06' THEN '6'
            WHEN '07' THEN '7'
            WHEN '08' THEN '8'
            WHEN '09' THEN '9'
            ELSE barf_import_reg_csv.GRADE
        END AS Grade
        ,barf_import_reg_csv.Gender AS Gender
        ,barf_import_reg_csv.BIRTHDATE AS DOB
        ,barf_import_reg_personal_csv.ETHNIC_CODE AS Race
        ,barf_import_reg_personal_csv.HISPANIC AS Hispanic_Latino
        ,barf_import_reg_personal_csv.ESL AS Ell_status
        ,CASE barf_import_reg_personal_csv.MEAL_STATUS
            WHEN '01' THEN 'F'
            WHEN '02' THEN 'R'
            WHEN '03' THEN 'P'
            WHEN '04' THEN 'F'
        END AS Frl_status
        ,barf_import_reg_personal_csv.HAS_IEP AS Iep_status
        ,student_contact.STREET_NAME AS Student_street
        ,student_contact.CITY AS Student_city
        ,student_contact.STATE AS Student_state
        ,student_contact.ZIP AS Student_zip
        ,student_contact.EMAIL AS Student_email
        ,CASE guardian1_contact.RELATION_CODE
            WHEN 'M' THEN 'Mother'
            WHEN 'F' THEN 'Father'
            WHEN 'P' THEN 'Both Parents'
            WHEN 'T' THEN 'Foster Parents'
            WHEN 'R' THEN 'Grandparent'
            /* I'm not doing anymore than this without an additional table */
            ELSE guardian1_contact.RELATION_CODE
        END AS Contact_relationship
        ,CASE guardian1_contact.CONTACT_TYPE 
            WHEN 'G' THEN 'guardian'
            ELSE ''
        END AS Contact_type
        ,(guardian1.FIRST_NAME || ' ' || guardian1.LAST_NAME) AS Contact_name
        ,contacts_phonenumber.PHONE AS Contact_phone
        ,guardian1.EMAIL AS Contact_email
        ,guardian1_contact.CONTACT_ID AS Contact_sis_id
        ,'' AS Username
        ,'' AS Password
        ,barf_import_regtb_language_csv.DESCRIPTION
    FROM barf_import_reg_csv
    LEFT JOIN barf_import_reg_personal_csv ON barf_import_reg_csv.STUDENT_ID = barf_import_reg_personal_csv.STUDENT_ID
    LEFT JOIN (SELECT * FROM barf_import_reg_stu_contact_csv WHERE CONTACT_TYPE = 'M') AS student_mailing_contact ON
        student_mailing_contact.STUDENT_ID = barf_import_reg_csv.STUDENT_ID
    LEFT JOIN barf_import_reg_contact_csv AS student_contact ON
        student_mailing_contact.CONTACT_ID = student_contact.CONTACT_ID
    LEFT JOIN (SELECT * FROM barf_import_reg_stu_contact_csv WHERE CONTACT_TYPE = 'G' AND CONTACT_PRIORITY = 1) AS guardian1_contact ON
        guardian1_contact.STUDENT_ID = barf_import_reg_csv.STUDENT_ID
    LEFT JOIN barf_import_reg_contact_csv AS guardian1 ON
        guardian1_contact.CONTACT_ID = guardian1.CONTACT_ID
    LEFT JOIN contacts_phonenumber ON guardian1_contact.CONTACT_ID = contacts_phonenumber.CONTACT_ID
    LEFT JOIN barf_import_regtb_language_csv ON 
        barf_import_reg_csv.LANGUAGE = barf_import_regtb_language_csv.CODE
    ORDER BY Student_id" | 
        Export-CSV -Path "students.csv" -NoTypeInformation -Force -Verbose -UseQuotes AsNeeded

#Sections
#We need a temp table with the secondary teachers.
Invoke-SqlUpdate -Query "CREATE TEMP TABLE IF NOT EXISTS secondary_teachers AS
    SELECT
        ROW_NUMBER () OVER (
            PARTITION BY SECTION_KEY
            ORDER BY SECTION_KEY
        ) RowNum
        ,SECTION_KEY
        ,STAFF_ID
    FROM barf_import_schd_ms_staff_csv"

Invoke-SqlQuery -Query "SELECT
        barf_import_schd_ms_csv.BUILDING AS School_id
        ,barf_import_schd_ms_csv.SECTION_KEY AS Section_id
        ,barf_import_schd_ms_session_csv.PRIMARY_STAFF_ID AS Teacher_id
        ,Teacher2.STAFF_ID AS Teacher_2_id
        ,Teacher3.STAFF_ID AS Teacher_3_id
        ,Teacher4.STAFF_ID AS Teacher_4_id
        ,(barf_import_schd_ms_session_csv.DESCRIPTION || ' - Period ' || barf_import_schd_ms_session_csv.START_PERIOD) AS Name
        ,barf_import_schd_ms_csv.COURSE_SECTION AS Section_number
        ,'' AS Grade
        ,barf_import_schd_ms_csv.DESCRIPTION AS Course_name
        ,barf_import_schd_ms_csv.COURSE AS Course_number
        ,barf_import_schd_ms_csv.DESCRIPTION AS Course_description
        ,barf_import_schd_ms_session_csv.START_PERIOD AS Period
        ,'' AS Subject
        ,barf_import_schd_ms_mp_csv.MARKING_PERIOD AS Term_name
        ,barf_import_reg_mp_dates_csv.START_DATE AS Term_start
        ,barf_import_reg_mp_dates_csv.END_DATE AS Term_end
    FROM barf_import_schd_ms_csv
    LEFT JOIN barf_import_schd_ms_session_csv ON
        barf_import_schd_ms_csv.SECTION_KEY = barf_import_schd_ms_session_csv.SECTION_KEY
    INNER JOIN barf_import_schd_ms_mp_csv ON
        barf_import_schd_ms_csv.SECTION_KEY = barf_import_schd_ms_mp_csv.SECTION_KEY
    LEFT JOIN barf_import_reg_mp_dates_csv ON
        barf_import_schd_ms_mp_csv.MARKING_PERIOD = barf_import_reg_mp_dates_csv.Marking_period
        AND barf_import_schd_ms_csv.BUILDING = barf_import_reg_mp_dates_csv.BUILDING
    INNER JOIN barf_import_schd_course_csv ON /* So we can limit to the ACTIVE_STATUS = 'Y' */
        barf_import_schd_ms_csv.COURSE = barf_import_schd_course_csv.COURSE
        AND barf_import_schd_ms_csv.BUILDING = barf_import_schd_course_csv.BUILDING
    LEFT JOIN secondary_teachers AS Teacher2 ON
        Teacher2.SECTION_KEY = barf_import_schd_ms_csv.SECTION_KEY
        AND Teacher2.RowNum = 1
    LEFT JOIN secondary_teachers AS Teacher3 ON
        Teacher3.SECTION_KEY = barf_import_schd_ms_csv.SECTION_KEY
        AND Teacher3.RowNum = 2
    LEFT JOIN secondary_teachers AS Teacher4 ON
        Teacher4.SECTION_KEY = barf_import_schd_ms_csv.SECTION_KEY
        AND Teacher4.RowNum = 3
    WHERE
        barf_import_schd_ms_csv.SCHOOL_YEAR = @schoolyear
    AND barf_import_schd_course_csv.ACTIVE_STATUS = 'Y'
    ORDER BY barf_import_schd_ms_csv.SECTION_KEY,barf_import_schd_ms_mp_csv.MARKING_PERIOD" -Parameters @{
        schoolyear = $schoolyear
    } | 
        Export-CSV -Path "sections.csv" -NoTypeInformation -Force -Verbose -UseQuotes AsNeeded

#Enrollments #Marking_period is not included in the final file upload. Which means there can be duplicates but it should be close enough to get us through this outage.
Invoke-SqlQuery -Query "SELECT
        barf_import_schd_ms_csv.BUILDING AS School_id
        ,barf_import_schd_stu_course_csv.SECTION_KEY AS Section_id
        ,barf_import_schd_stu_course_csv.STUDENT_ID AS Student_id
        /*,barf_import_schd_ms_mp_csv.MARKING_PERIOD AS Marking_period*/
    FROM  barf_import_schd_stu_course_csv
    LEFT JOIN barf_import_schd_ms_csv ON
        barf_import_schd_stu_course_csv.SECTION_KEY = barf_import_schd_ms_csv.SECTION_KEY
    INNER JOIN barf_import_schd_ms_mp_csv ON
        barf_import_schd_ms_csv.SECTION_KEY = barf_import_schd_ms_mp_csv.SECTION_KEY
    LEFT JOIN barf_import_schd_stu_conf_mp_csv schd_stu_conf_mp USING (STUDENT_ID,SECTION_KEY) /* This limits to enrollments that haven't been altered by schd_stu_course */
    LEFT JOIN barf_import_schd_stu_crs_dates_csv schd_stu_crs_dates USING (STUDENT_ID,SECTION_KEY) /* This is used to limit the classes that have been dropped */
    WHERE schd_stu_conf_mp.STUDENT_ID IS NULL
    AND schd_stu_crs_dates.DATE_DROPPED = ''
    AND barf_import_schd_stu_course_csv.COURSE_STATUS != ('D')

    UNION

    /* Modifications to enrollments are in schd_stu_conf_mp and have to be accounted for separately */
    SELECT
        barf_import_schd_ms_csv.BUILDING AS School_id
        ,barf_import_schd_stu_conf_mp_csv.SECTION_KEY AS Section_id
        ,barf_import_schd_stu_conf_mp_csv.STUDENT_ID AS Student_id
        /*,barf_import_schd_stu_conf_mp_csv.MARKING_PERIOD AS Marking_period*/
    FROM barf_import_schd_stu_conf_mp_csv
    INNER JOIN barf_import_schd_ms_csv USING (SECTION_KEY)
    INNER JOIN barf_import_schd_stu_course_csv USING (STUDENT_ID,SECTION_KEY)
    WHERE barf_import_schd_stu_course_csv.COURSE_STATUS != ('D')" |
        Export-CSV -Path "enrollments.csv" -NoTypeInformation -Force -Verbose -UseQuotes AsNeeded

#teachers
Invoke-SqlQuery -Query "SELECT
        barf_import_reg_staff_bldgs_csv.BUILDING AS 'School_id'
        ,barf_import_reg_staff_bldgs_csv.STAFF_ID AS 'Teacher_id'
        ,barf_import_reg_staff_bldgs_csv.STAFF_ID AS 'Teacher_number'
        ,barf_import_reg_staff_csv.STAFF_STATE_ID AS 'State_teacher_id'
        ,barf_import_reg_staff_csv.EMAIL AS 'Teacher_email'
        ,barf_import_reg_staff_csv.FIRST_NAME AS 'First_name'
        ,barf_import_reg_staff_csv.MIDDLE_NAME AS 'Middle_name'
        ,barf_import_reg_staff_csv.LAST_NAME AS 'Last_name'
        ,'' AS 'Title'
        ,'' AS 'Username'
        ,'' AS 'Password'
    FROM barf_import_reg_staff_bldgs_csv
    LEFT JOIN barf_import_reg_staff_csv USING (STAFF_ID)
    WHERE 
        barf_import_reg_staff_bldgs_csv.ACTIVE = 'Y'
    AND
        barf_import_reg_staff_bldgs_csv.IS_TEACHER = 'Y'
    AND
        barf_import_reg_staff_csv.STAFF_ID != 0" |
        Export-CSV -Path "teachers.csv" -NoTypeInformation -Force -Verbose -UseQuotes AsNeeded
    
#schools
Invoke-SqlQuery -Query "SELECT
	barf_import_reg_building_csv.BUILDING AS School_id
	,barf_import_reg_building_csv.NAME AS School_name
	,barf_import_reg_building_csv.STATE_CODE_EQUIV AS School_number
	,barf_import_reg_building_csv.STATE_CODE_EQUIV AS State_id
	,'' AS Low_grade
	,'' AS High_grade
	,barf_import_reg_building_csv.PRINCIPAL AS Principal
	,'' AS Principal_email
	,barf_import_reg_building_csv.STREET1 AS School_address
	,barf_import_reg_building_csv.CITY AS School_city
	,barf_import_reg_building_csv.STATE AS School_state
	,barf_import_reg_building_csv.ZIP AS School_zip
	,barf_import_reg_building_csv.PHONE AS School_phone
FROM barf_import_reg_building_csv
WHERE
	barf_import_reg_building_csv.TRANSFER_BUILDING != 'Y'
AND
	barf_import_reg_building_csv.BUILDING < 8000" |
        Export-CSV -Path "schools.csv" -NoTypeInformation -Force -Verbose -UseQuotes AsNeeded