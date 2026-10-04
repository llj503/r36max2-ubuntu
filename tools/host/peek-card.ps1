$u = Get-Content -Path 'J:\uInitrd' -Encoding Byte -TotalCount 8
"working uInitrd magic : " + (($u | ForEach-Object { $_.ToString('x2') }) -join '')
$i = Get-Content -Path 'J:\Image' -Encoding Byte -TotalCount 64
"working Image tag     : " + (($i[56..63] | ForEach-Object { $_.ToString('x2') }) -join '') + "   (52414d64 = 'ARMd' arm64)"
"working dtb size      : " + (Get-Item 'J:\rk3326-r36max2-linux.dtb').Length
