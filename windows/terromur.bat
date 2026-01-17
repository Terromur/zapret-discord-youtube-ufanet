@echo off
chcp 65001 > nul
:: 65001 - UTF-8

cd /d "%~dp0"
call service.bat status_zapret
call service.bat check_updates
call service.bat load_game_filter
echo:

set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
cd /d %BIN%
start "zapret: %~n0" /min "%BIN%winws.exe" --wf-tcp=80,443,2053,2083,2087,2096,8443,%GameFilter% --wf-udp=443,19294-19344,50000-50100,1024-65535 ^
--filter-udp=19294-19344,50000-50100 --filter-l7=stun,discord --dpi-desync=fake --dpi-desync-repeats=12 --new ^
--filter-tcp=443,2053,2083,2087,2096,8443 --hostlist-domains=discord-attachments-uploads-prd.storage.googleapis.com --dpi-desync=multidisorder --dpi-desync-split-pos=2 --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=2053,2083,2087,2096,8443 --hostlist-domains=discord.media --dpi-desync=multisplit --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443,2053,2083,2087,2096,8443 --hostlist-domains=cdn.localizeapi.com --dpi-desync=fake --dpi-desync-fooling=md5sig --dup=1 --dup-cutoff=n2 --dup-fooling=md5sig --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=443 --hostlist="%LISTS%list-google.txt" --dpi-desync=multidisorder --dpi-desync-split-pos=midsld --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%cloudflare_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-fooling=md5sig --dup=1 --dup-cutoff=n2 --dup-fooling=md5sig --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%constant_plain_ipv4.txt" --dpi-desync=fakedsplit --dpi-desync-ttl=4 --dpi-desync-split-pos=midsld --dpi-desync-fakedsplit-mod=altorder=1 --dpi-desync-repeats=6 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%digitalocean_plain_ipv4.txt" --dpi-desync=multisplit --dpi-desync-split-pos=sniext+4 --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%hetzner_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-ttl=1 --dpi-desync-autottl=-2 --orig-ttl=1 --orig-mod-start=s1 --orig-mod-cutoff=d1 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%oracle_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-ttl=1 --dpi-desync-autottl=-2 --orig-ttl=1 --orig-mod-start=s1 --orig-mod-cutoff=d1 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%ipset-fastly.txt" --dpi-desync=multisplit --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%akamai_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-fooling=md5sig --dup=1 --dup-cutoff=n2 --dup-fooling=md5sig --dpi-desync-repeats=12 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-tcp=80,443 --ipset="%LISTS%cdn77_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-fooling=md5sig --dup=1 --dup-cutoff=n2 --dup-fooling=md5sig -dpi-desync-repeats=12 --dpi-desync-fake-tls=%BIN%tls_clienthello_4pda_to.bin --new ^
--filter-tcp=80,443 --ipset="%LISTS%scaleway_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-ttl=1 --dpi-desync-autottl=-2 --orig-ttl=1 --orig-mod-start=s1 --orig-mod-cutoff=d1 --dpi-desync-fake-tls="%BIN%tls_clienthello_4pda_to.bin" --new ^
--filter-udp=443 --ipset="%LISTS%all_plain_ipv4.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=12 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="%BIN%quic_initial_www_google_com.bin" --dup-cutoff=n2 --new


