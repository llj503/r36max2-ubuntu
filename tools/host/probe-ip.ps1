param([string]$Ip = "192.168.31.58")
$ErrorActionPreference = 'SilentlyContinue'
"=== ping $Ip ==="
Test-Connection -ComputerName $Ip -Count 3 | Select-Object Address,IP4Address,ResponseTime | Format-Table -AutoSize
"=== tcp ports ==="
foreach ($p in 22,80,443,5353,5900) {
  $t = New-Object System.Net.Sockets.TcpClient
  try {
    $a = $t.BeginConnect($Ip, $p, $null, $null)
    $ok = $a.AsyncWaitHandle.WaitOne(1500)
    if ($ok -and $t.Connected) {
      "open  : $p"
      if ($p -eq 22) {
        $s = $t.GetStream(); $b = New-Object byte[] 80
        $s.ReadTimeout = 1500
        try { $n = $s.Read($b, 0, 80); "banner: " + ([Text.Encoding]::ASCII.GetString($b, 0, $n)).Trim() } catch { "banner: <no read>" }
      }
    } else { "closed: $p" }
  } catch { "closed: $p ($($_.Exception.Message))" }
  $t.Close()
}
"=== arp entry ==="
arp -a | Select-String $Ip
