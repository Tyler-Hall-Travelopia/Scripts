# Get input from user
$SourceUser = Read-Host "Enter the samAccountName of the user to copy"
$NewUserFirstName = Read-Host "Enter the first name of the new user"
$NewUserSurname = Read-Host "Enter the surname of the new user"



# Construct the new user's name and email address
$NewUserName = "$NewUserFirstName.$NewUserSurname"
$NewUserEmail = "$NewUserName@ email domain"

# Check if the new user already exists
if (Get-ADUser -Filter "SamAccountName -eq '$NewUserName'") {
    Write-Host "A user with the SamAccountName '$NewUserName' already exists. Please choose a different name."
    exit
}

# Get the source user object
$User = Get-ADUser $SourceUser -Properties memberOf, proxyAddresses, EmailAddress

# Get the OU path for the new user from the source user object
$OU = ($User.DistinguishedName -split ',', 2)[1]

# Create the new user object
$NewUserParams = @{
    Name = "$NewUserFirstName $NewUserSurname"
    GivenName = $NewUserFirstName
    Surname = $NewUserSurname
    DisplayName = "$NewUserFirstName $NewUserSurname"
    SamAccountName = $NewUserName
    UserPrincipalName = "$NewUserEmail"
    AccountPassword = (ConvertTo-SecureString "Password123" -AsPlainText -Force)
    Enabled = $true
    Path = $OU
}
try {
    New-ADUser @NewUserParams
} catch {
    Write-Host "Error creating new user: $($_.Exception.Message)"
    exit
}

# Add the user to the same groups as the source user
foreach ($Group in $User.memberOf) {
    Add-ADGroupMember -Identity $Group -Members $NewUserName
}

# Get the email addresses and replace the username in each address
$EmailAddresses = $User.proxyAddresses | ForEach-Object {
    if ($_ -like "SMTP:*") {
        # Replace the username in the primary SMTP address
        $_ -replace $User.SamAccountName, $NewUserName
    } elseif ($_ -like "smtp:*") {
        # Replace the username in a secondary email address that starts with "smtp"
        $_ -replace "(?<=smtp:)[^@]+", $NewUserName
    } else {
        # Keep any other types of addresses as-is
        $_
    }
}

# Update the email addresses and proxy addresses on the new user
try {
    Set-ADUser -Identity $NewUserName -EmailAddress "$NewUserEmail"
    Set-ADUser -Identity $NewUserName -Replace @{proxyAddresses=$EmailAddresses}
} catch {
    Write-Host "Error setting email and proxy addresses: $($_.Exception.Message)"
}
