$ErrorActionPreference = 'SilentlyContinue'
"=== ping 192.168.31.209 ==="
ping -n 3 -w 1500 192.168.31.209 | Select-String 'TTL|无法访问|Request|timed'
""
"=== port probe 192.168.31.209 ==="
foreach ($p in 22,2222,80,8080,53,111,3000) {
  $c = New-Object System.Net.Sockets.TcpClient
  try {
    $r = $c.BeginConnect("192.168.31.209", $p, $null, $null)
    if ($r.AsyncWaitHandle.WaitOne(700)) { $c.EndConnect($r); "  port $p : OPEN" }
    else { "  port $p : filtered/timeout" }
  } catch { "  port $p : refused ($($_.Exception.InnerException.Message))" }
  finally { $c.Close() }
}
""
"=== neighbours (ARP/NDP) ==="
Get-NetNeighbor -IPAddress 192.168.31.20* | Select-Object IPAddress,LinkLayerAddress,State | Format-Table -AutoSize | Out-String -Width 90
""
"=== reverse: does 209 answer SSH banner on 22? ==="
$c = New-Object System.Net.Sockets.TcpClient
try { $c.Connect("192.168.31.209",22); $s=$c.GetStream(); $b=New-Object byte[] 64; $n=$s.Read($b,0,64); [System.Text.Encoding]::ASCII.GetString($b,0,$n) } catch { "  no banner: $($_.Exception.Message)" } finally { $c.Close() }
