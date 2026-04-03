// QUERY: Units (static lookup table)
// Paste this into: Home > Transform Data > New Source > Blank Query > Advanced Editor

let
    Source = #table(
        type table [UnitKey = text, UnitLabel = text, UnitType = text, MaxBeds = number, PayrollBU = text],
        {
            {"1East", "1 East - Child Acute", "acute", 18, "Acute Adult-100E"},
            {"2East", "2 East - Adult Acute", "acute", 20, "Acute Child-200E"},
            {"2West", "2 West - Adolescent", "acute", 20, "Acute Adol-200W"},
            {"3East", "3 East - Adult Acute", "acute", 20, "Acute Adult-300E"},
            {"3West", "3 West - Adult Acute", "acute", 20, "Acute Adult-300W"},
            {"HRC",   "HRC - SUD/Detox ASAM 3.7", "detox", 16, "Acute Adult-100"}
        }
    )
in
    Source
