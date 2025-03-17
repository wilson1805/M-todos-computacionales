using LinearAlgebra
using DataFrames
using CSV
using Plots
using StatsPlots
using Dates
using Statistics
using Clustering

# Función para calcular la matriz de admitancia Ybus
function calcular_b(lines, nodes)
    NN = nrow(nodes)
    NL = nrow(lines)
    Ybus = zeros(Complex{Float64}, NN, NN)

    for k in 1:NL
        n1B = parse(Int, lines.FROM[k][2:end]) # Nodo envío
        n2B = parse(Int, lines.TO[k][2:end]) # Nodo recibo

        yLB = 1 / (lines.R[k] + lines.X[k] * 1im) # Admitancia serie
        Bs = lines.B[k] * 1im / 2 # Elemento shunt Y/2
        Ybus[n1B, n1B] += yLB + Bs
        Ybus[n1B, n2B] -= yLB
        Ybus[n2B, n1B] -= yLB
        Ybus[n2B, n2B] += yLB + Bs
    end

    return Ybus
end

# Función para calcular el flujo de carga
function FFC(nodes, Ybus, VN)
    NN = size(nodes, 1)
    YNN = Ybus[2:end, 2:end] # Quita la primera fila y columna
    YNS = Ybus[2:end, 1] # Primera columna sin el primer elemento

    VS = nodes.VPU[1] + nodes.ANG[1] * 1im # Tensión del Slack

    PNE = zeros(NN)
    QNE = zeros(NN)
    SN = zeros(Complex{Float64}, NN)

    for i in 2:NN
        PN = nodes.PGEN[i] - nodes.PLOAD[i]
        QN = nodes.QGEN[i] - nodes.QLOAD[i]
        PNE[i] += PN
        QNE[i] += QN
        SN[i] = PN + QN * 1im
    end

    SN = SN[2:end]
    div = conj(SN ./ VN)
    YNNINV = inv(YNN)

    T = YNNINV * (div - YNS * VS)
    return T
end

# Función para iterar el flujo de carga
function iterar_FFC(nodes, Ybus)
    max_iter = 20
    tol = 1e-6
    YNN = Ybus[2:end, 2:end]
    VN = ones(Complex{Float64}, size(YNN, 2))
    errors = Float64[]
    voltages = []

    for iter in 1:max_iter
        T = FFC(nodes, Ybus, VN)
        VN_new = T

        error = norm(VN_new - VN)
        push!(errors, error)
        push!(voltages, copy(VN_new))

        if error < tol
            break
        end

        VN = VN_new
    end

    return VN, errors, voltages
end

# Función para calcular los promedios de ppd y pps
function promedio(pro_solar, pro_dem)
    pro_solar.Fecha = Date.(pro_solar.Fecha, DateFormat("mm/dd/yyyy"))
    ppd = Matrix{Float64}(undef, 55, 24)
    base_powerd = 100
    base_powerg = 100000

    for i in 1:55
        for j in 1:24
            start_idx = (j-1)*60 + 1
            end_idx = j*60
            ppd[i, j] = mean(pro_dem[start_idx:end_idx, i]) / base_powerd
        end
    end

    pps = Matrix{Float64}(undef, 365, 24)
    for day in 1:365
        for hour in 1:24
            start_idx = (day - 1) * 24 * 12 + (hour - 1) * 12 + 1
            end_idx = start_idx + 11
            pps[day, hour] = mean(pro_solar.Potencia[start_idx:end_idx]) / base_powerg
        end
    end

    return ppd, pps
end

# Función para ajustar PGEN
function ajustar_PGEN!(nodes, valor, nodo)
    nodes.PGEN[nodo] += valor
end

# Función para aplicar kmeans a pps
function apply_kmeans(pps)
    k = 3
    result = kmeans(pps', k)
    clusters = result.assignments
    centroids = result.centers'
    sorted_indices = sortperm([mean(centroids[i, :]) for i in 1:k])
    sorted_centroids = centroids[sorted_indices, :]
    return sorted_centroids
end

# Función para calcular el flujo de carga diario con PGEN
function flujo_carga_diario_con_PGEN(lines, nodes, ppd, reduced_pps, caso, nodo_pgen, Ybus)
    final_voltages_matrix = Matrix{Complex{Float64}}(undef, 906, 24)

    for hora in 1:24
        nodes.PLOAD .= 0.0

        for (i, idx) in enumerate(pq_indices)
            nodes.PLOAD[idx] += ppd[i, hora]
        end

        valor = reduced_pps[caso, hora]
        ajustar_PGEN!(nodes, valor, nodo_pgen)

        VN_final, errors, voltages = iterar_FFC(nodes, Ybus)

        final_voltages_matrix[:, hora] = vcat(nodes.VPU[1], VN_final)



        
    end

    return final_voltages_matrix
end

# Función para calcular el flujo de carga diario sin PGEN
function flujo_carga_diario_sin_PGEN(lines, nodes, ppd, Ybus)
    final_voltages_matrix = Matrix{Complex{Float64}}(undef, 906, 24)

    for hora in 1:24
        nodes.PLOAD .= 0.0
        nodes.PGEN .= 0.0

        for (i, idx) in enumerate(pq_indices)
            nodes.PLOAD[idx] += ppd[i, hora]
        end

        VN_final, errors, voltages = iterar_FFC(nodes, Ybus)

        final_voltages_matrix[:, hora] = vcat(nodes.VPU[1], VN_final)
    end

    return final_voltages_matrix
end

# Función para calcular las pérdidas de potencia activa
function calcular_perdidas(Ybus, voltages_matrix)
    perdidas_P = Float64[]
    for hora in 1:size(voltages_matrix, 2)
        V_hora = voltages_matrix[:, hora]
        Sper_hora = V_hora' * Ybus * V_hora
        push!(perdidas_P, real(Sper_hora))
    end
    return perdidas_P
end

function ICC(Ybus, nodo_pgen, final_voltages_matrix_con_PGEN, final_voltages_matrix_sin_PGEN)
    ICCC = zeros(Float64, 24)
    ICCS = zeros(Float64, 24)
    Zth = 0.004*im
    Z = Ybus
    Z[1,1] +=1/Zth
    Zbus = inv(Ybus)
    ZKK = Zbus[nodo_pgen,nodo_pgen]
    for hora in 1:24
        VC = abs(final_voltages_matrix_con_PGEN[nodo_pgen,hora])
        VS = abs(final_voltages_matrix_sin_PGEN[nodo_pgen,hora])
        IccC = VC/ZKK
        IccS = VS/ZKK
        ICCC[hora]+=abs(IccC)
        ICCS[hora]+=abs(IccS)
    end
    return ICCC, ICCS
end

# Cargar los datos
lines = DataFrame(CSV.File("lines.csv"))
nodes = DataFrame(CSV.File("nodes.csv"))
pro_solar = CSV.read("SolarData.csv", DataFrame)
pro_dem = CSV.read("Demandas.csv", DataFrame)

Ybus = calcular_b(lines, nodes)
ppd, pps = promedio(pro_solar, pro_dem)
PLOAD_original = copy(nodes.PLOAD)
pq_indices = findall(x -> x != 0, nodes.PLOAD)
reduced_pps = apply_kmeans(pps)
caso = 3
nodo_pgen = 885

# Calcular el flujo de carga diario con y sin PGEN
final_voltages_matrix_con_PGEN = flujo_carga_diario_con_PGEN(lines, nodes, ppd, reduced_pps, caso, nodo_pgen, Ybus)
final_voltages_matrix_sin_PGEN= flujo_carga_diario_sin_PGEN(lines, nodes, ppd, Ybus)

# Calcular los valores mínimos y máximos para cada columna con PGEN
#min_valuesC = minimum(norm(final_voltages_matrix_con_PGEN), dims=1)
#max_valuesC = maximum(norm(final_voltages_matrix_con_PGEN), dims=1)

# Convertir los resultados a vectores
#min_valuesC = vec(min_valuesC)
#max_valuesC = vec(max_valuesC)

# Calcular los valores mínimos y máximos para cada columna sin PGEN
#min_valuesS = minimum(norm(final_voltages_matrix_sin_PGEN), dims=1)
#max_valuesS = maximum(norm(final_voltages_matrix_sin_PGEN), dims=1)

# Convertir los resultados a vectores
#min_valuesS = vec(min_valuesS)
#max_valuesS = vec(max_valuesS)


# Calcular las pérdidas de potencia activa
perdidas_P_con_PGEN = calcular_perdidas(Ybus, final_voltages_matrix_con_PGEN)
perdidas_P_sin_PGEN = calcular_perdidas(Ybus, final_voltages_matrix_sin_PGEN)

# Calcular la ICC
ICCC, ICCS = ICC(Ybus, nodo_pgen, final_voltages_matrix_con_PGEN, final_voltages_matrix_sin_PGEN)

#Gradicar las tensiones máximas y míinimos con y sin 

#v = plot(1:24, max_valuesS, label="Tensiones máximas con GD", xlabel="Hora", ylabel="Tensión pu", title="Tensión durante el Día", legend=:topright, grid=true)
#v = plot!(1:24, min_valuesS, label="Tensiones míinimos con GD")
#v = plot!(1:24, max_valuesC, label="Tensiones máxima sin GD")
#v = plot!(1:24, min_valuesC, label="Tensiones míinimos sin GD")
#savefig("tensiones.png")

# Graficar la ICC diaria
a = plot(1:24, ICCC, label="ICC con GD", xlabel="Hora", ylabel="Corriente de Cortocircuito (ICC)", title="Corriente de Cortocircuito durante el Día", legend=:topright, grid=true)
a = plot!(1:24, ICCS, label="ICC sin GD")
savefig("ICC3.png")

# Graficar la comparación de pérdidas de potencia activa
b = plot(1:24, perdidas_P_con_PGEN, label="Con Paneles Solares", xlabel="Hora", ylabel="Pérdidas de Potencia Activa (P)", title="Comparación de Pérdidas de Potencia Activa con y sin Paneles Solares", legend=:topright, grid=true)
b = plot!(1:24, perdidas_P_sin_PGEN, label="Sin Paneles Solares")
savefig("P3.png")

# Generar el informe en formato Markdown
markdown_content = """
# Estudio de Conexión Simplificado en el Marco de la Resolución CREG 174 de 2021

El siguiente documento presenta un estudio de Conexión Simplificada el cual se aplica a una red de 907 nodos. El estudio 
consiste en la conexión de un Generador Distribuido (GD) de generación solar en el nodo 885. Se analizan tres casos de 
estudio: potencia máxima, media y mínima en el GD. En este estudio solo se tiene una curva de demanda, la cual se 
considera como demanda máxima. Además, se evalúa el aporte del GD al cortocircuito y finalmente el estudio de pérdidas 
en todo el sistema.

Como primer caso, se analiza el sistema sin generación distribuida (GD) para conocer su estado actual (ver Fig. 1). Se determina que la tensión mínima es de 0.898617 pu en el nodo 885 a las 19 horas, por lo que se decide conectar los GD en este punto.

![alt text](Tesiones_max_caso0.png)
![alt text](VC0.jpeg)
Fig. 1. Tensiones máximas y mínimas en el sistema sin GD.

También se presentan los tres casos de estudio solicitados (ver Fig. 2.): generación máxima, mínima y promedio.
![alt text](Casos_estudio.png)
Fig. 2. Casos de estudio.


## Lineamientos para la Realización de los Análisis que Componen el Estudio de Conexión Simplificado


### Definición de Escenarios:


Aunque en el estudio solo se pide el flujo de carga en un punto específo, los resultador que se van a mostrar contiene 
el flujo de carga en todo un día

- Simulación de condiciones más desfavorables en términos de requerimientos de red.
- Escenarios a considerar:

  - **Carga pura**: Demanda máxima con mínima generación.
  ![alt text](Tesiones_max_caso1.png)
  ![alt text](VC1.jpeg)
  Fig. 3. Demanda máxima con mínima generación.


  Con la instalación de la generación distribuida (GD), se observa que, con la mínima generación, la tensión mínima se presenta en el nodo 618 con un valor de 0.913109 pu a las 19 horas (ver Fig. 3).

  - **Momento de máxima diferencia**: Máxima generación y mínima demanda.
  ![alt text](Tesiones_max_caso3.png)
  ![alt text](VC3.jpeg)
  Fig. 4. Máxima generación y mínima demanda.
  
  En este caso, se observa que con la generación máxima, la tensión mínima se presenta en el nodo 638 con un valor de 0.9182230 pu (ver Fig. 4) a las 10 horas.


  - **Máxima demanda y generación promedio**: Coincidencia en el tiempo de generación promedio y máxima demanda.
    ![alt text](Tesiones_max_caso2.png)
    ![alt text](VC2.jpeg)
    Fig. 5. generación promedio y máxima demanda.

    En este caso, se observa que con la generación promedio, la tensión mínima se presenta en el nodo 638 con un valor de 0.917085 pu (ver Fig. 4) a las 10 horas.


### Cálculo de Contribución a la Corriente de Cortocircuito:

  Para esta parte, dado que el nodo está tan alejado de la subestación (885), la corriente de cortocircuito (ICC) no es tan elevada como si estuviera cerca de la fuente. Además, con la incorporación de la generación distribuida (GD), el valor de la tensión aumenta, lo cual hace que el valor de la ICC también aumente.

  - Calcular nuevos valores de intensidad de fase máxima ante cortocircuito (caso 1 - mínima generación).
  ![alt text](ICC1.png)
  Fig. 6. Icc con mínima generación.

  - Calcular nuevos valores de intensidad de fase máxima ante cortocircuito (caso 2- mediana generación).
  ![alt text](ICC2.png)
  Fig. 7. Icc con mediana generación.

  - Calcular nuevos valores de intensidad de fase máxima ante cortocircuito (caso 3- máxima generación).
  ![alt text](ICC3.png)
  Fig. 8. Icc con máxima generación.


  Como se observa en las imágenes anteriores, a medida que se incrementa la generación, la ICC aumenta hasta un valor de 1.76955 pu cuando la generación es máxima. Por el contrario, cuando no se tiene generación distribuida (GD), la ICC máxima es de 1.7363248 pu.


### Análisis de Pérdidas

  Las pérdidas se ven acontinuación:

  - Establecer el incremento o disminución del nivel de pérdidas por la conexión del sistema de generación (caso 1 - generación mínima).
  ![alt text](P1.png)
  Fig. 9. Pérdidas de P con mínima generación.

  - Calcular el nivel de pérdidas con y sin el proyecto (caso 1).

  Sin el proyecto se tienen unas pérdias de 0.032 pu y con este del 0.026 pu.
  Se observa una disminución de las pérdidas en todo el sistema, tomando como referencia las pérdidas máximas en el caso 1, con una disminución alrededor del 18.75%.

  - Establecer el incremento o disminución del nivel de pérdidas por la conexión del sistema de generación (caso 2 - generación media).
  ![alt text](P2.png)
  Fig. 10. Pérdidas de P con mediana generación.

  - Calcular el nivel de pérdidas con y sin el proyecto (caso 2).

  Sin el proyecto se tienen unas pérdias de 0.032 pu y con este del 0.022 pu.
  Se observa una disminución de las pérdidas en todo el sistema, tomando como referencia las pérdidas máximas en el caso 2, con una disminución alrededor del 31.25%.

  - Establecer el incremento o disminución del nivel de pérdidas por la conexión del sistema de generación (caso 3 - generación máxima).
  ![alt text](P3.png)
  Fig. 11. Pérdidas de P con máxima generación.

  - Calcular el nivel de pérdidas con y sin el proyecto (caso 3).

  Sin el proyecto se tienen unas pérdias de 0.032 pu y con este del 0.019 pu.
  Se observa una disminución de las pérdidas en todo el sistema, tomando como referencia las pérdidas máximas en el caso 3, con una disminución alrededor del 40.625%.

Se observa que la implementación de la generación distribuida (GD) implica un aumento de la corriente de cortocircuito (ICC). Sin embargo, como punto positivo, se logra ver una disminución de las pérdidas y un aumento de las tensiones en el sistema.
"""

# Guardar el informe en un archivo Markdown
open("Reporte_Estudio_Conexión.md", "w") do f
    write(f, markdown_content)
end

println("El informe se ha generado y guardado como 'Reporte_Estudio_Conexión.md'.")


