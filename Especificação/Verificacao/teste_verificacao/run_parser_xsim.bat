@echo off
setlocal
cd /d "%~dp0"

echo ========================================
echo TESTE DO PACKET PARSER - PCAP DIRETO
echo ========================================

if not exist "sim\trafego_referencia_P01_P14.pcap" (
    echo ERRO: PCAP nao encontrado.
    pause
    exit /b 1
)

copy /Y "sim\trafego_referencia_P01_P14.pcap" "trafego_referencia_P01_P14.pcap"

echo.
echo [1/3] Compilando Packet Parser e testbench...

call xvlog -sv rtl\packet_parser.sv tb\tb_packet_parser_pcap.sv > xvlog_parser.log 2>&1
set "RC=%ERRORLEVEL%"
type xvlog_parser.log

if not "%RC%"=="0" (
    echo ERRO NA COMPILACAO: %RC%
    pause
    exit /b %RC%
)

echo.
echo [1/3] COMPILACAO CONCLUIDA!

echo.
echo [2/3] Elaborando testbench...

call xelab tb_packet_parser_pcap -s tb_packet_parser_pcap_sim > xelab_parser.log 2>&1
set "RC=%ERRORLEVEL%"
type xelab_parser.log

if not "%RC%"=="0" (
    echo ERRO NA ELABORACAO: %RC%
    pause
    exit /b %RC%
)

echo.
echo [2/3] ELABORACAO CONCLUIDA!

echo.
echo [3/3] Executando simulacao...

call xsim tb_packet_parser_pcap_sim -runall > xsim_parser.log 2>&1
set "RC=%ERRORLEVEL%"
type xsim_parser.log

if not "%RC%"=="0" (
    echo ERRO NA SIMULACAO: %RC%
    pause
    exit /b %RC%
)

echo.
echo ========================================
echo SIMULACAO CONCLUIDA!
echo ========================================

pause
exit /b 0