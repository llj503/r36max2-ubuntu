$ErrorActionPreference = 'SilentlyContinue'
"=== ARP table (192.168.31.x) ==="
arp -a | Select-String '192\.168\.31\.'
""
"=== scanning 192.168.31.1-254 for open TCP/22 (120ms each) ==="
$found = @()
1..254 | ForEach-Object {
  $ip = "192.168.31.$_"
  $c = New-Object System.Net.Sockets.TcpClient
  try {
    $r = $c.BeginConnect($ip, 22, $null, $null)
    if ($r.AsyncWaitHandle.WaitOne(120)) {
      $c.EndConnect($r)
      $found += $ip
      "  SSH OPEN: $ip"
    }
  } catch {} finally { $c.Close() }
}
""
"=== hosts with SSH: $($found.Count) ==="
$found
