function Get-FinVizFilters {
    param (
        [String[]]$Filter
    )
    $BaseURL = "https://finviz.com/screener.ashx?v=111&ft=4"
    $ErrorActionPreference = "SilentlyContinue"
    $All = Invoke-WebRequest -Uri $BaseURL
    ${Filters-Cells} = @()
    foreach ($i in $All.ParsedHtml.body.getElementsByClassName("filters-cells")){
        ${Filters-Cells} += $i
    }
    $title = @()
    $text = @()
    foreach ($i in ${Filters-Cells}){
        if ($i.innerHTML -like "<SPAN*"){
            $title += $i
        } else {
            $innerText = $i.innerText
            if ($innerText -ne "" -and $innerText -ne " " -and $null -ne $innerText){
                $text += $i
            }
        }
    }
    $Options = $All.ParsedHtml.body.getElementsByClassName("screener-combo-text")
    Add-Type -TypeDefinition @"
    public struct FVFilter {
        public string Description;
        public string Filter;
        public object[] Values;
    }
"@ -ErrorAction SilentlyContinue
    function SortVals {
        param (
            $ti,
            $te,
            $int
        )
        $Percent = 100*($int/67)
        Write-Progress -Activity "Sorting Filters" -PercentComplete $Percent -Status $ti
        $Opt = $Options[$int]
        $Opt = $Opt | Where-Object {$_.text -notlike "*Elite only*" -and $_.text -ne "Any"}
        $FCount = $Opt.Count
        $FInt = 100/$FCount
        $Perc = 0
        $FilterVals = foreach ($i in $Opt){
            $ValDesc = $i.Text
            Write-Progress -id 1 -Activity "Sorting Values for $ti" -PercentComplete $Perc -CurrentOperation $ValDesc
            $ValVal = $i.attributes | Where-Object nodename -eq value | Select-Object -expand value
            $prop = [ordered]@{
                Description = $ValDesc
                Value = $ValVal
                Enable = $false
            }
            New-Object PSObject -Property $prop
            $Perc += $FInt
        }
        [FVFilter]@{
            Description = $ti
            Filter = $te
            Values = $FilterVals
        }
    }
    for ($integer = 0 ; $integer -lt $title.Count ; $integer ++){
        $desc = $title[$integer].innerText
        $filt = ($text[$integer].innerHTML -split 'data-filter="')[1].Split('"')[0]
        if ($Filter){
            if ($Filter -contains $desc -or $Filter -contains $filt){
                SortVals -ti $desc -te $filt -int $integer
            }
        } else {
            SortVals -ti $desc -te $filt -int $integer
        }
    }
}
function Set-FinVizFilters {
    [CmdletBinding(
        DefaultParameterSetName = 'Single'
    )]
    param (
        [Parameter(
            ValueFromPipeline = $true,
            ParameterSetName = 'Single',
            Mandatory = $true
        )]
        [Parameter(
            ValueFromPipeline = $true,
            ParameterSetName = 'Hash',
            Mandatory = $true
        )]
        $FinVizFilter,
        [Parameter(
            ValueFromPipeline = $true,
            ParameterSetName = 'Single',
            Mandatory = $true
        )]
        <#[ValidateScript({
            if ($FinVizFilter.Description -contains $_ -or $FinVizFilter.Filter -contains $_){
                $true
            } else {
                Throw [System.Management.Automation.ItemNotFoundException] "The filter `"$_`" is not found in the Filter Set provided by the FinVizFilter parameter."
            }
        })]#>$Filter,
        [Parameter(
            ParameterSetName = 'Single',
            Mandatory = $true
        )]
        <#[ValidateScript({
            $Values = ($FinVizFilter | Where-Object { $_.Description -eq $Filter -or $_.Filter -eq $Filter}).Values
            if ($Values.Description -contains $_ -or $Values.Value -contains $_){
                $true
            } else {
                Throw [System.Management.Automation.ItemNotFoundException] "The value `"$_`" is not found under the Filter `"$Filter`" in the Filter Set provided in the FinVizFilter parameter."
            }
        })]#>$Value,
        [Parameter(
            ParameterSetName = 'Hash',
            Mandatory = $true
        )]
        <#[ValidateScript({
            foreach ($K in $_.Keys){
                if (!($FinVizFilter.Description -contains $K -or $FinVizFilter.Filter -contains $K)){
                    Write-Warning "The filter `"$K`" is not found in the Filter Set provided by the FinVizFilter parameter. It will be skipped."
                } else {
                    $Val = $_[$K]
                    $Filter = $FinVizFilter | Where-Object { $_.Description -eq $K -or $_.Filter -eq $K }
                    if (!($Filter.Values.Description -contains $Val -or $Filter.Values.Value -contains $Val)){
                        Write-Warning "The value `"$Val`" is not found under the Filter `"$K`" in the Filter Set provided in the FinVizFilter parameter. It will be skipped."
                    }
                }
            }
            $true
        })]#>
        [Hashtable]$Hashtable
    )
    Begin {
        function SetVal {
            param (
                $In,
                $Filt,
                $Val
            )
            $NewArr = @()
            foreach ($Item in $In){
                $D = $Item.Description
                $F = $Item.Filter
                if ($Filt -eq $D -or $Filt -eq $F){
                    $Vs = @()
                    foreach ($V in $Item.Values){
                        if ($V.Description -eq $Val -or $V.Value -eq $Val){
                            $Vs += [PSCustomObject]@{
                                Description = $V.Description
                                Value = $V.Value
                                Enable = $true
                            }
                        } else {
                            $Vs += $V
                        }
                    }
                } else {
                    $Vs = $Item.Values
                }
                [FVFilter]@{
                    Description = $D
                    Filter = $F
                    Values = $Vs
                }
            }
        }
    }
    Process {
        $NewFilter = $FinVizFilter
        switch ($PSCmdlet.ParameterSetName){
            'Single' {
                SetVal -In $FinVizFilter -Filt $Filter -Val $Value
            }
            'Hash' {
                foreach ($Key in $Hashtable.Keys){
                    $NewFilter = SetVal -In $NewFilter -Filt $Key -Val $Hashtable[$Key]
                }
                $NewFilter
            }
        }
    }
}
function Get-FinVizURLs {
    param (
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        $FinVizFilter,
        [switch]$SingleQuery
    )
    Begin {
        $BaseURL = "https://finviz.com/screener.ashx?v=111"
        $FilterList = @()
        $SearchURL = ""
    }
    Process {
        switch ($SingleQuery){
            $true {
                foreach ($Filter in $FinVizFilter){
                    $Description = $Filter.Description
                    $BaseFilter = $Filter.Filter
                    $Values = $Filter.Values | Where-Object Enable -eq $true
                    if ($Values.Count -gt 0){
                        Write-Warning "Multiple values selected for $Description. Only the first value will be used."
                        $Values = $Values[0]
                    }
                    if ($Values.Count -ne 0){
                        $Val = $Values.Description
                        $SearchQuery = $BaseFilter,$Values.Value -join '_'
                        if ($SearchURL -ne ""){
                            $SearchURL += ','
                        }
                        $SearchURL += $SearchQuery
                        $FilterList += [PSCustomObject]@{
                            Filter = $Description
                            Value = $Val
                        }
                    }
                }
            }
            $false {
                foreach ($Filter in $FinVizFilter){
                    $Description = $Filter.Description
                    $BaseFilter = $Filter.Filter
                    $ModURL = $BaseURL + $BaseFilter + "_"
                    foreach ($Val in $Filter.Values){
                        if ($Val.Enable -eq $true){
                            $FinalURL = $ModURL + $Val.Value + "&ft=4"
                            [PSCustomObject]@{
                                Filter = $Description
                                Value = $Val.Description
                                URL = $FinalURL
                            }
                        }
                    }
                }
            }
        }
    }
    End {
        if ($SingleQuery){
            $URL = if ($FilterList.Count -gt 0){
                $BaseURL + '&f=' + $SearchURL + '&ft=4'
            } else {
                $BaseURL + '&ft=4'
            }
            [PSCustomObject]@{
                SearchFilter = $FilterList
                URL = $URL
            }
        }
    }
}