$ErrorActionPreference = 'SilentlyContinue'
"=== mDNS / DNS name ==="
Resolve-DnsName r36max2.local -Type A | Select-Object Name,IPAddress | Format-Table -AutoSize
Resolve-DnsName r36max2 -Type A | Select-Object Name,IPAddress | Format-Table -AutoSize
"=== ping attempts ==="
foreach ($h in @('r36max2.local','192.168.31.250','192.168.31.209')) {
  $p = Test-Connection -ComputerName $h -Count 1 -TimeoutSeconds 1
  if ($p) { "reply: $h -> $($p.IPAddress)" } else { "no reply: $h" }
}
"=== ARP (full) ==="
arp -a | Select-String '192.168.31'
"=== TCP/22 sweep ==="
$found = @()
$jobs = 1..254 | ForEach-Object {
  $ip = "192.168.31.$_"
  $c = New-Object Net.Sockets.TcpClient
  $a = $c.BeginConnect($ip,22,$null,$null)
  [PSCustomObject]@{ ip=$ip; c=$c; a=$a }
}
Start-Sleep -Milliseconds 5000
foreach ($j in $jobs) {
  try { if ($j.c.Connected) { $found += $j.ip } } catch {}
  try { $j.c.Close() } catch {}
}
"hosts with TCP/22 open: $($found -join ', ')"
if ($found.Count -eq 0) { "none" }
