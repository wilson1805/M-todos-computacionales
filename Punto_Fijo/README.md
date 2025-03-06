# MÉTODO DEL PUNTO FIJO PARA RESOLVER FLUJOS DE CARGA

## Descripción General
Este script en Julia realiza cálculos de flujo de carga en un sistema de energía eléctrica. Utiliza varias bibliotecas como `LinearAlgebra`, `DataFrames`, `CSV`, `Plots`, `StatsPlots`, `Dates` y `Statistics` para manejar datos, realizar cálculos y generar gráficos.

## Funciones

### 1. `calcular_b(lines, nodes)`
Calcula la matriz de admitancia `Ybus` del sistema.

- **Entradas:**
  - `lines`: DataFrame con los datos de las líneas de transmisión.
  - `nodes`: DataFrame con los datos de los nodos del sistema.

- **Salidas:**
  - `Ybus`: Matriz de admitancia compleja del sistema.

- **Teoría:**
  La matriz de admitancia `Ybus` es fundamental en el análisis de sistemas de potencia, representando las relaciones entre las tensiones y corrientes en los nodos del sistema.

### 2. `FFC(nodes, Ybus, VN)`
Calcula el flujo de carga en el sistema.

- **Entradas:**
  - `nodes`: DataFrame con los datos de los nodos.
  - `Ybus`: Matriz de admitancia del sistema.
  - `VN`: Vector de tensiones nodales iniciales.

- **Salidas:**
  - `T`: Vector de tensiones nodales calculadas.

- **Teoría:**
  El flujo de carga es un cálculo esencial en la operación de sistemas de potencia, determinando las tensiones, corrientes y potencias en cada nodo del sistema.

### 3. `iterar_FFC(nodes, Ybus)`
Itera el cálculo del flujo de carga hasta alcanzar la convergencia.

- **Entradas:**
  - `nodes`: DataFrame con los datos de los nodos.
  - `Ybus`: Matriz de admitancia del sistema.

- **Salidas:**
  - `VN`: Vector de tensiones nodales finales.
  - `errors`: Vector de errores de cada iteración.
  - `voltages`: Lista de vectores de tensiones nodales en cada iteración.

- **Teoría:**
  La iteración del flujo de carga es necesaria ya que el teorema del punto fijo trata de aplicar "transformaciones" hasta llegar a un punto (converge), ajustando las tensiones nodales hasta que los errores sean mínimos.

### 4. `promedio(pro_solar, pro_dem)`
Calcula los promedios de potencia demandada (`ppd`) y potencia solar producida (`pps`).

- **Entradas:**
  - `pro_solar`: DataFrame con los datos de potencia solar.
  - `pro_dem`: DataFrame con los datos de demanda de potencia.

- **Salidas:**
  - `ppd`: Matriz de promedios de potencia demandada.
  - `pps`: Matriz de promedios de potencia solar producida.

- **Teoría:**
  Los promedios de potencia son útiles para analizar patrones de consumo y generación de energía a lo largo del tiempo. Esto también se hace para no sacar un flujo de carga por minuto.

### 5. `ajustar_PGEN!(nodes, valor, nodo)`
Ajusta la generación de potencia en un nodo específico.

- **Entradas:**
  - `nodes`: DataFrame con los datos de los nodos.
  - `valor`: Valor de ajuste de la generación de potencia.
  - `nodo`: Índice del nodo a ajustar.

- **Salidas:**
  - Ninguna (modifica el DataFrame `nodes` directamente).

### 6. `flujo_carga_diario(lines, nodes, ppd, pps, dia, nodo_pgen)`
Calcula el flujo de carga diario para un día específico.

- **Entradas:**
  - `lines`: DataFrame con los datos de las líneas de transmisión.
  - `nodes`: DataFrame con los datos de los nodos.
  - `ppd`: Matriz de promedios de potencia demandada.
  - `pps`: Matriz de promedios de potencia solar producida.
  - `dia`: Día específico para el cálculo.
  - `nodo_pgen`: Nodo específico para ajustar la generación de potencia.

- **Salidas:**
  - `max_tensiones`: Vector de tensiones máximas por hora.
  - `min_tensiones`: Vector de tensiones mínimas por hora.
  - `nodos_max`: Vector de nodos con tensiones máximas por hora.
  - `nodos_min`: Vector de nodos con tensiones mínimas por hora.
  - `tensiones_max`: Lista de pares (nodo, tensión máxima) por hora.
  - `tensiones_min`: Lista de pares (nodo, tensión mínima) por hora.

## Ejecución del Script
1. Cargar los datos de las líneas y nodos desde archivos CSV.
2. Calcular los promedios de potencia demandada y solar.
3. Guardar el vector original de potencia demandada (`PLOAD`).
4. Encontrar los índices de los nodos PQ.
5. Elegir el día y el nodo para ajustar la generación de potencia.
6. Calcular el flujo de carga diario.
7. Mostrar y graficar los resultados de tensiones máximas y mínimas.

## Requisitos
- Julia 1.6 o superior.
- Paquetes: `LinearAlgebra`, `DataFrames`, `CSV`, `Plots`, `StatsPlots`, `Dates`, `Statistics`.

