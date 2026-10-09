# Bloco Flow Finalizer (FF)

**Status:** Em implementação --- interface e larguras precisam de validação final

## 1. Objetivo

O **Flow Finalizer** (FF) irá receber do Controller um registro de fluxo já atualizado pela Flow Table e transformará
os dados acumulados em um vetor de features.

Após o alinhamento discutido na reunião, a responsabilidade do FF fica restrita à **finalização do fluxo**. A lógica de atualização dos dados
do fluxo permanece no Controller/etapa de atualização, não no Finalizer.

## 2. Funções

O módulo deve:

1.  Receber o registro completo de um fluxo e um sinal que autorize a finalização.
2.  Extrair os campos necessários do registro recebido.
3.  Calcular a duração do fluxo:
    `duration = last_timestamp - first_timestamp`
4.  Montar o vetor de features na ordem e com as larguras definidas pela interface do projeto.
5.  Sinalizar a conclusão da operação por meio de `finalize_done`.


## 3. Interface do módulo

### 3.1 Interface proposta após o alinhamento

A anotação da reunião mais recente indica as seguintes larguras para a
interface:

  -----------------------------------------------------------------------------------------
  Sinal              Tipo                  Largura indicada Descrição
  ------------------ ---------------- --------------------- -------------------------------
  `flow_entry`       Entrada                       384 bits Registro completo do fluxo 
                                                            proveniente da Flow Table

  `finalize_en`      Entrada                          1 bit Autoriza/dispara a finalização
                                                            do registro válido

  `feature_vector`   Saída                         280 bits Vetor de features gerado 
                                                            pelo módulo Finalizer

  `finalize_done`    Saída                            1 bit Indica que a geração do vetor
                                                            foi concluída
  ----------------------------------------------------------------------------

### 3.2 Referência de largura

As larguras dos dados de entrada e saída ainda precisam ser confirmadas após o alinhamento com a equipe, 
considerando a estrutura atual da Flow Table e a composição final do vetor de features.

## 4. Cálculo da duração

A duração será calculada pela diferença entre o timestamp final e o timestamp inicial:

```
duration = last_timestamp - first_timestamp
```

Considerando que os timestamps possuem 48 bits, é necessário confirmar se essa representação será mantida na 
estrutura atual de flow_entry ou se haverá alguma alteração.

## 5. Sequência de operação do módulo

1.  O Controller disponibiliza um `flow_entry` válido.
2.  O Controller ativa `finalize_en` para solicitar a finalização.
3.  O Flow Finalizer irá checar os campos do registro e calcular a `duration`.
4.  O Flow Finalizer deverá montar e disponibilizar `feature_vector`.
5.  O Flow Finalizer ativará a `finalize_done` para informar que a operação terminou.
6.  O Controller utiliza a conclusão para coordenar o processamento seguinte/a definir.

O comportamento exato dos sinais ainda será definido na implementação e alinhado com a equipe. 
Entre os pontos a definir estão a duração do pulso de finalize_done (1 bit?), a necessidade de um sinal ready e a 
possibilidade de implementar um timeout para evitar que o módulo fique aguardando indefinidamente.

## 6. Diagrama funcional

``` mermaid
flowchart LR
    C[Controller] -->|flow_entry| F[Flow Finalizer]
    C -->|finalize_en| F
    F --> D[Calcular duration]
    D --> V[Montar feature_vector]
    V -->|feature_vector| O[Etapa seguinte]
    F -->|finalize_done| C
```

## 7. Pontos pendentes de validação

-   Confirmar as larguras finais de `flow_entry` e `feature_vector` (384/280 bits ou outro).
-   Confirmar tamanho de `first_timestamp` e `last_timestamp` no registro de entrada - 48 bits.
-   Definir o comportamento de `finalize_en` e `finalize_done` e a duração do pulso de conclusão.
-   Confirmar se há necessidade de sinal tipo `ready` ou se `finalize_done` é suficiente para coordenar o próximo registro.
-   Confirmar se no módulo será colocado timeout para evitar travamentos/erros.
-   Alinhar a nomenclatura dos sinais com os demais módulos

## 8. Plano de implementação do código 

1. Confirmar a interface e as larguras dos campos com a equipe.
2. Criar a estrutura RTL do módulo e configurar o ambiente de simulação no Vivado.
3. Implementar a extração dos campos e o cálculo da duração.
4. Implementar a montagem do vetor de features.
5. Implementar a sinalização de conclusão.
6. Criar um testbench com registros simulados, incluindo timestamps definidos diretamente nos estímulos.
7. Verificar as larguras, a ordem dos campos e os valores de saída durante a simulação.
8. Validar individualmente o Flow Finalizer e, após essa etapa, integrá-lo com o Controller.

