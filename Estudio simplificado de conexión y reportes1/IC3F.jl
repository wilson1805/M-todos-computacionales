using LinearAlgebra
using DataFrames
using CSV
using Plots

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
        #println(abs(IccC), abs(IccS))
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
final_voltages_matrix_sin_PGEN = flujo_carga_diario_sin_PGEN(lines, nodes, ppd, Ybus)

# Calcular las pérdidas de potencia activa
perdidas_P_con_PGEN = calcular_perdidas(Ybus, final_voltages_matrix_con_PGEN)
perdidas_P_sin_PGEN = calcular_perdidas(Ybus, final_voltages_matrix_sin_PGEN)


#Caclular la ICC
ICCC, ICCS = ICC(Ybus,nodo_pgen, final_voltages_matrix_con_PGEN, final_voltages_matrix_sin_PGEN)

# Graficar la ICC diaria
a = plot(1:24, ICCC, label="ICC con GD", xlabel="Hora", ylabel="Corriente de Cortocircuito (ICC)", title="Corriente de Cortocircuito durante el Día", legend=:topright, grid=true)
a = plot!(1:24, ICCS, label="ICC sin GD")
display(a)
#savefig("ICC2.png")

# Imprimir los resultados
#println("Pérdidas de potencia activa con PGEN: ", perdidas_P_con_PGEN)
#println("Pérdidas de potencia activa sin PGEN: ", perdidas_P_sin_PGEN)


# Graficar la comparación de pérdidas de potencia activa
b = plot(1:24, perdidas_P_con_PGEN, label="Con Paneles Solares", xlabel="Hora", ylabel="Pérdidas de Potencia Activa (P)", title="Comparación de Pérdidas de Potencia Activa con y sin Paneles Solares", legend=:topright, grid=true)
b = plot!(1:24, perdidas_P_sin_PGEN, label="Sin Paneles Solares")
display(b)
#savefig("P2.png")


