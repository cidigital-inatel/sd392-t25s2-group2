@echo off
setlocal
cd /d "%~dp0"

echo ==========================================
echo TESTE DIRIGIDO - COLISAO CRC16 / FLOW TABLE
echo ==========================================

echo.
echo [1/3] Compilando RTLs e testbench de colisao...
call xvlog -sv ^
 rtl\feature_pipeline\flow_identification_unit.sv ^
 rtl\feature_pipeline\hash_unit.sv ^
 rtl\feature_pipeline\fiu_hash_top.sv ^
 rtl\feature_pipeline\controller_base.sv ^
 rtl\feature_pipeline\flow_table.sv ^
 rtl\feature_pipeline\flow_finalizer.sv ^
 rtl\feature_pipeline\top_extracao_features_entrada.sv ^
 tb\tb_colisao_hash_flowtable.sv > collision_xvlog.log 2>&1
set "RC=%ERRORLEVEL%"
type collision_xvlog.log
if not "%RC%"=="0" goto erro_compilacao

echo.
echo [2/3] Elaborando testbench de colisao...
call xelab tb_colisao_hash_flowtable -s tb_colisao_hash_flowtable_sim > collision_xelab.log 2>&1
set "RC=%ERRORLEVEL%"
type collision_xelab.log
if not "%RC%"=="0" goto erro_elaboracao

echo.
echo [3/3] Executando teste dirigido...
call xsim tb_colisao_hash_flowtable_sim -runall > collision_xsim.log 2>&1
set "RC=%ERRORLEVEL%"
type collision_xsim.log
if not "%RC%"=="0" goto erro_simulacao

echo.
echo ==========================================
echo TESTE DE COLISAO CONCLUIDO!
echo ==========================================
pause
exit /b 0

:erro_compilacao
echo ERRO NA COMPILACAO: %RC%
pause
exit /b %RC%
:erro_elaboracao
echo ERRO NA ELABORACAO: %RC%
pause
exit /b %RC%
:erro_simulacao
echo ERRO NA SIMULACAO: %RC%
pause
exit /b %RC%
