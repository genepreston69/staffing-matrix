// PARAMETER: SharePointSiteURL
// Paste this into: Home > Manage Parameters > New Parameter
// Name: SharePointSiteURL
// Type: Text
// Current Value: (your SharePoint site URL)

let
    Source = "https://YOUR_TENANT.sharepoint.com/sites/YOUR_SITE" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]
in
    Source
