$ErrorActionPreference = 'Stop'
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -Scope User -PythonPath '/usr/local/bin/python' -Confirm:$false | Out-Null

$zips = @(Get-ChildItem /data -File -Filter *.zip)
if ($zips.Count -eq 0) { throw 'put the ESXi depot zip and driver zips in the mounted /data directory' }

$ordered = @($zips | Where-Object Name -match 'depot') + @($zips | Where-Object Name -notmatch 'depot')
$base = $null
foreach ($z in $ordered) {
    $depot = Add-EsxSoftwareDepot $z.FullName
    if (@(Get-EsxImageProfile).Count -gt 0) { $base = $z; break }
    Remove-EsxSoftwareDepot -SoftwareDepot $depot -Confirm:$false | Out-Null
}
if (-not $base) { throw 'no zip contains an image profile' }

$before = @{}
Get-EsxSoftwarePackage | ForEach-Object { $before["$($_.Name)|$($_.Version)"] = $true }

foreach ($z in $zips | Where-Object FullName -ne $base.FullName) {
    Write-Host "depot $($z.Name)"
    Add-EsxSoftwareDepot $z.FullName | Out-Null
}
$added = @(Get-EsxSoftwarePackage | Where-Object { -not $before.ContainsKey("$($_.Name)|$($_.Version)") })
Write-Host ("new packages: " + (($added | ForEach-Object Name) -join ', '))

$kind = if ($env:ESXI_PROFILE_KIND) { $env:ESXI_PROFILE_KIND } else { 'standard' }
$src = Get-EsxImageProfile | Where-Object Name -like "*-$kind" | Select-Object -First 1
if (-not $src) { throw "profile *-$kind not found" }

$dst = "$($src.Name)-custom"
$vendor = if ($env:ESXI_VENDOR) { $env:ESXI_VENDOR } else { 'custom' }
New-EsxImageProfile -CloneProfile $src.Name -Name $dst -Vendor $vendor | Out-Null
Set-EsxImageProfile -ImageProfile $dst -AcceptanceLevel CommunitySupported -Confirm:$false | Out-Null

function Get-BootbankNames($text) {
    [regex]::Matches($text, '_bootbank_(.+?)_\d') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
}

foreach ($pkg in $added) {
    $ok = $false
    for ($i = 0; $i -lt 6; $i++) {
        try {
            Add-EsxSoftwarePackage -ImageProfile $dst -SoftwarePackage $pkg -ErrorAction Stop | Out-Null
            Write-Host "added $($pkg.Name)"
            $ok = $true
            break
        } catch {
            $msg = $_.Exception.Message
            $present = @(Get-EsxSoftwarePackage -ImageProfile $dst | Select-Object -ExpandProperty Name)
            $remove = @(Get-BootbankNames $msg | Where-Object { $_ -ne $pkg.Name -and $present -contains $_ })
            if ($remove.Count -eq 0 -and $msg -match 'already') { $remove = @($pkg.Name) }
            if ($remove.Count -eq 0) { throw }
            foreach ($name in $remove) {
                Write-Host "conflict: remove $name"
                $old = Get-EsxSoftwarePackage -ImageProfile $dst -Name $name
                Remove-EsxSoftwarePackage -ImageProfile $dst -SoftwarePackage $old -Confirm:$false | Out-Null
            }
        }
    }
    if (-not $ok) { throw "failed to add $($pkg.Name)" }
}

$iso = if ($env:ESXI_ISO) { $env:ESXI_ISO } else { "/data/$dst.iso" }
Export-EsxImageProfile -ImageProfile $dst -ExportToIso -FilePath $iso -Force -NoSignatureCheck
Write-Host "wrote $iso"
