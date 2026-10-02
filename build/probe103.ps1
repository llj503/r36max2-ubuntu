$ErrorActionPreference = 'SilentlyContinue'
"=== mDNS name ==="
Resolve-DnsName r36max2.local -Type A | Select-Object Name,IPAddress | Format-Table -AutoSize
Resolve-DnsName r36max2 -Type A | Select-Object Name,IPAddress | Format-Table -AutoSize
"=== ping .103 ==="
Test-Connection -ComputerName 192.168.31.103 -Count 2 | Select-Object Address,ResponseTime,IPv4Address | Format-Table -AutoSize
"=== ssh banner via TCP ==="
$c = New-Object Net.Sockets.TcpClient
try { $c.Connect('192.168.31.103', 22); $s = $c.GetStream(); $b = New-Object byte[] 64; $n = $s.Read($b,0,64); "banner: " + [Text.Encoding]::ASCII.GetString($b,0,$n) } catch { "connect failed: $_" }
$c.Close()
"=== port check 22/5353/80 ==="
foreach ($p in 22,80,5353) { $t = New-Object Net.Sockets.TcpClient; try { $t.Connect('192.168.31.103',$p); "open: $p" } catch { "closed: $p" }; $t.Close() }
"=== arp ==="
arp -a | Select-String '192.168.31'
