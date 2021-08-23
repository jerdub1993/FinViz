function Get-FVFilters {
    param (
        [String[]]$Filter
    )
    if (!($Filter)){
        Write-Warning "Since a Filter has not been specified this cmdlet will process all FinViz filters, which may take a significant amount of time."
    }
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
        $Percent = 100*($int/$title.Count)
        Write-Progress -Activity "Sorting Filters" -PercentComplete $Percent -Status $ti
        $Opt = $Options[$int]
        $Opt = $Opt | Where-Object {$_.text -notlike "*Elite only*" -and $_.text -ne "Any"}
        $FCount = $Opt.Count
        $FInt = 100/$FCount
        $Perc = 0
        $FilterVals = foreach ($i in $Opt){
            $ValDesc = $i.Text
            Write-Progress -id 1 -Activity "Sorting Values for $ti" -PercentComplete $Perc -CurrentOperation $ValDesc
            $ValVal = $i.value
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
function Set-FVFilters {
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
            ParameterSetName = 'Single',
            Mandatory = $true
        )]
        $Filter,
        [Parameter(
            ParameterSetName = 'Single',
            Mandatory = $true
        )]
        $Value,
        [Parameter(
            ParameterSetName = 'Hash',
            Mandatory = $true
        )]
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
function Get-FVURLs {
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
function Get-FVStocks {
    [CmdletBinding(
        DefaultParameterSetName = 'URL',
        SupportsShouldProcess,
        ConfirmImpact = 'Medium'
    )]
    param (
        [Parameter(
            ParameterSetName = 'Filter'
        )]
        $FinVizFilter,
        [Parameter(
            ParameterSetName = 'URL',
            ValueFromPipelineByPropertyName = $true
        )]
        [string]$URL = "https://finviz.com/screener.ashx?v=111&ft=4",
        [Parameter(
            ParameterSetName = 'Filter'
        )]
        [Parameter(
            ParameterSetName = 'URL'
        )]
        [switch]$FormatCurrency
    )
    function ToNumber {
    param([string] $NumberString)
    $multipliers = @{
        'T' = 1000000000000
        'B' = 1000000000
        'M' = 1000000
        'K' = 1000
        '' = 1
    }
    switch -regex ($numberString)
    {
        '^(?<base>[\d\.]+)(?<suffix>\w*)$'
        {
            $base = [double] $matches['base']
            $multiplier = [int64] $multipliers[$matches['suffix']]

            if($multiplier)
            {
                [int64]($base * $multiplier)
            }
            else
            {
                throw "$($matches['suffix']) is an unknown suffix"
            }
        }
    }
    }
    function ToCurrency {
        param (
            [ValidateSet("USD","EUR","GBP")]$C = "USD",
            [int64]$Num,
            [switch]$Decimal
        )
        if ($Decimal){
            $N = 2
        } else {
            $N = 0
        }
        $Symbols = @{
            "USD" = "$"
            "EUR" = "€"
            "GBP" = "£"
        }
        $Sym = $Symbols[$C]
        $Price = $Sym + $("{0:N$N}" -f $Num)
        return $Price
    }
    if ($PSCmdlet.ParameterSetName -eq 'Filter'){
        $URL = Get-FVURLs -FinVizFilter $FinVizFilter -SingleQuery | Select-Object -ExpandProperty URL
    }
    $WR = Invoke-WebRequest -Uri $URL
    [int]$TotalResults = ($WR.ParsedHtml.Body.getElementsByClassName("count-text") | Where-Object InnerText -like Total* | Select-Object -ExpandProperty InnerText).Split() | Where-Object {$_ -notlike "Total*" -and $_ -notlike "#*"}
    [int]$TotalPages = if ($TotalResults -le 20){
        1
    } else {
        $WR.ParsedHtml.Body.getElementsByClassName("screener-pages") | Select-Object -ExpandProperty InnerText -Last 1
    }
    if ($TotalPages -gt 15){
        $ConfirmPreference = 'Medium'
    } else {
        $ConfirmPreference = 'High'
    }
    if ($PSCmdlet.ShouldProcess("$URL ($TotalPages pages)",$PSCmdlet.MyInvocation.InvocationName)){
        for ($Page = 0; $Page -lt $TotalPages; $Page++){
            $Count = 1 + $Page*20
            $PageURL = $URL + "&r=$Count"
            $PageWR = Invoke-WebRequest -Uri $PageURL
            $PageStocks = $PageWR.ParsedHtml.Body.getElementsByClassName("screener-link-primary")
            $PageStockData = $PageWR.ParsedHtml.Body.getElementsByClassName("screener-link") | ForEach-Object {
                $Property = @{
                    innerText = $_.innerText
                    search = $_.search
                }
                New-Object PSObject -Property $Property
            }
            $ParameterNames = $PageWR.ParsedHtml.Body.getElementsByClassName("table-top") | ForEach-Object {$_.innerText}
            foreach ($Stock in $PageStocks){
                $Ticker = $Stock.innerText
                $BaseSearch = $Stock.pathname
                $Search = $Stock.search
                $Data = $PageStockData | Where-Object search -eq $Search | ForEach-Object {$_.innerText}
                $Hash = [ordered]@{}
                $Hash.Ticker = $Ticker
                for ($PN = 1; $PN -lt $ParameterNames.Count; $PN++){
                    Remove-Variable Dat -Confirm:$false -ErrorAction SilentlyContinue
                    $Parameter = $ParameterNames[$PN]
                    switch ($FormatCurrency){
                        $true {
                            switch ($Parameter) {
                                'Market Cap' {$Dat = ToCurrency -Num (ToNumber -NumberString $Data[$PN])}
                                'Price' {$Dat = ToCurrency -Num $Data[$PN] -Decimal}
                                'Volume' {[int64]$Dat = $Data[$PN]}
                                'Change' {[float]$Dat = $Data[$PN].Trim('%')}
                                Default {$Dat = $Data[$PN]}
                            }
                        }
                        $false {
                            switch ($Parameter) {
                                'Market Cap' {[int64]$Dat = ToNumber -NumberString $Data[$PN]}
                                'Price' {[float]$Dat = $Data[$PN]}
                                'Volume' {[int64]$Dat = $Data[$PN]}
                                'Change' {[float]$Dat = $Data[$PN].Trim('%')}
                                Default {$Dat = $Data[$PN]}
                            }
                        }
                    }
                    $Hash.$Parameter = $Dat
                }
                $Hash.URL = "https://finviz.com/" + $BaseSearch + $Search
                New-Object PSObject -Property $Hash
            }
        }
    }
}
function Get-FVTickerData {
    [CmdletBinding(
        DefaultParameterSetName = 'Ticker'
    )]
    param (
        [Parameter(
            ParameterSetName = 'Ticker',
            Mandatory = $true
        )]
        [string]$Ticker,
        [Parameter(
            ParameterSetName = 'URL',
            ValueFromPipelineByPropertyName = $true,
            Mandatory = $true
        )]
        [string]$URL
    )
    if ($PSCmdlet.ParameterSetName -eq 'Ticker'){
        $URL = "https://finviz.com/quote.ashx?t=" + $Ticker + "&ty=c&p=d&b=1"
    }
    $WR = Invoke-WebRequest -Uri $URL
    function ToNumber {
        param([string] $NumberString)
        $multipliers = @{
            'T' = 1000000000000
            'B' = 1000000000
            'M' = 1000000
            'K' = 1000
            '' = 1
        }
        switch -regex ($numberString)
        {
            '^(?<base>[\d\.]+)(?<suffix>\w*)$'
            {
                $base = [double] $matches['base']
                $multiplier = [int64] $multipliers[$matches['suffix']]
    
                if($multiplier)
                {
                    [int64]($base * $multiplier)
                }
                else
                {
                    throw "$($matches['suffix']) is an unknown suffix"
                }
            }
        }
    }
    function ToCurrency {
        param (
            [ValidateSet("USD","EUR","GBP")]$C = "USD",
            [int64]$Num,
            [switch]$Decimal
        )
        if ($Decimal){
            $N = 2
        } else {
            $N = 0
        }
        $Symbols = @{
            "USD" = "$"
            "EUR" = "€"
            "GBP" = "£"
        }
        $Sym = $Symbols[$C]
        $Price = $Sym + $("{0:N$N}" -f $Num)
        return $Price
    }
    $Parsed = $WR.ParsedHtml
    $Title = $Parsed.Title
    $Ticker = $Title.Split()[0]
    $Company = $Title.Trim($Ticker).Trim("Stock Quote").Trim()
    $Table = $Parsed.getElementsByTagName("TABLE") | ForEach-Object {
        if ($_.classname -eq 'snapshot-table2'){$_}
    }
    $Titles = $Table.getElementsByClassName('snapshot-td2-cp') | ForEach-Object {$_.innerText}
    $Data = $Table.getElementsByClassName('snapshot-td2') | ForEach-Object {$_.innerText}
    $Hash = @{}
    $Hash.Ticker = $Ticker
    $Hash.Company = $Company
    $Hash.FinVizURL = $URL
    $Hash.CompanyURL = $Parsed.body.getElementsByClassName('tab-link') | ForEach-Object {
        if ($_.innerText -eq $Company){
            $_.href
        }
    }
    $BigNum = @(
        'Market Cap',
        'Income',
        'Sales',
        'Shs Outstand',
        'Shs Float',
        'Avg Volume'
    )
    for ($int = 0; $int -lt $Titles.Count; $int++){
        Remove-Variable D -Confirm:$false -ErrorAction SilentlyContinue
        $T = $Titles[$int]
        $D = $Data[$int]
        if ($D.Trim() -like '*%' -and $T -ne 'Volatility'){
            $T = $T + ' %'
            $D = $D.Trim('%')
        }
        if ($BigNum -contains $T){
            [int64]$D = ToNumber -NumberString $D
        } elseif ($T -eq '52W Range') {
            [float[]]$D = $D.Split('-').Trim()
        } elseif ($T -eq 'Volatility'){
            $Arr = $D.Split().Trim('%')
            $D = [ordered]@{}
            $Week = $Arr[0]
            $Month = $Arr[1]
            [float]$D.Week = $Week
            [float]$D.Month = $Month
            $T = $T + ' %'
        } elseif ($T -eq 'Volume') {
            [int64]$D = $D
        } else {
            try {
                [float]$D = $D
            }
            catch {
                $D = $D
            }
        }
        $Hash.$T = $D
    }
    New-Object PSObject -Property $Hash
}
