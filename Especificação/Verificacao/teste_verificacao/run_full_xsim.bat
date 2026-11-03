@echo off
setlocal
cd /d "%~dp0"

echo ==========================================
echo INTEGRACAO COMPLETA - PCAP A FEATURES
echo ==========================================

echo.
echo Verificando arquivos...

if not exist "sim\trafego_referencia_P01_P14.pcap" (
    echo ERRO: PCAP nao encontrado.
    pause
    exit /b 1
)

if not exist "sim\feature_vectors_esperados.mem" (
    echo ERRO: Vetores esperados nao encontrados.
    pause
    exit /b 1
)

copy /Y "sim\trafego_referencia_P01_P14.pcap" "trafego_referencia_P01_P14.pcap" >nul
copy /Y "sim\feature_vectors_esperados.mem" "feature_vectors_esperados.mem" >nul

echo.
echo [1/3] Compilando RTLs e testbench integrado...

call xvlog -sv ^
 rtl\packet_parser.sv ^
 rtl\feature_pipeline\flow_identification_unit.sv ^
 rtl\feature_pipeline\hash_unit.sv ^
 rtl\feature_pipeline\fiu_hash_top.sv ^
 rtl\feature_pipeline\controller_base.sv ^
 rtl\feature_pipeline\flow_table.sv ^
 rtl\feature_pipeline\flow_finalizer.sv ^
 rtl\feature_pipeline\top_extracao_features_entrada.sv ^
 tb\tb_pcap_to_features.sv > full_xvlog.log 2>&1

set "RC=%ERRORLEVEL%"
type full_xvlog.log

if not "%RC%"=="0" goto erro_compilacao

echo.
echo COMPILACAO CONCLUIDA!

echo.
echo [2/3] Elaborando testbench integrado...

call xelab tb_pcap_to_features -s tb_pcap_to_features_sim > full_xelab.log 2>&1

set "RC=%ERRORLEVEL%"
type full_xelab.log

if not "%RC%"=="0" goto erro_elaboracao

echo.
echo ELABORACAO CONCLUIDA!

echo.
echo [3/3] Executando simulacao integrada...

call xsim tb_pcap_to_features_sim -runall > full_xsim.log 2>&1

set "RC=%ERRORLEVEL%"
type full_xsim.log

if not "%RC%"=="0" goto erro_simulacao

echo.
echo ==========================================
echo SIMULACAO INTEGRADA CONCLUIDA!
echo ==========================================

pause
exit /b 0

:erro_compilacao
echo ERRO NA COMPILACAO. Codigo: %RC%
pause
exit /b %RC%

:erro_elaboracao
echo ERRO NA ELABORACAO. Codigo: %RC%
pause
exit /b %RC%

:erro_simulacao
echo ERRO NA SIMULACAO. Codigo: %RC%
pause
exit /b %RC%