using LinearAlgebra
using DataFrames
using CSV
using Plots
using StatsPlots
using Dates
using Statistics

# Función para calcular la matriz de admitancia Ybus
function calcular_b(lines, nodes)
    NN = nrow(nodes)
    NL = nrow(lines) 
    Ybus = zeros(NN, NN) * 1im 

    for k in 1:NL
        # Modelo matemático pi de la línea
        n1B = lines.FROM[k][2:end] # Nodo envío
        n2B = lines.TO[k][2:end] # Nodo recibo
        n1B = parse(Int, n1B) # Convertir el str en un entero
        n2B = parse(Int, n2B)

        yLB = 1 / (lines.R[k] + lines.X[k] * 1im) # Admitancia serie
        Bs = lines.B[k] * 1im / 2 # Elemento shunt Y/2
        Ybus[n1B, n1B] += yLB + Bs 
        Ybus[n1B, n2B] -= yLB 
        Ybus[n2B, n1B] -= yLB # Fuera diagonal
        Ybus[n2B, n2B] += yLB + Bs # Diagonal
    end

    return Ybus
end

# Función para calcular el flujo de carga
function FFC(nodes, Ybus, VN)
    NN = size(nodes, 1)
    YNN = Ybus[2:end, 2:end] # Quita la primera fila y columna
    YNS = Ybus[1:end, 1:1] #
    YNS = YNS[2:end] # Quita la primera fila

    VS = nodes.VPU[2] + nodes.ANG[2] * 1im # Tensión del Slack

    PNE = zeros(NN)
    QNE = zeros(NN)
    SN = zeros(Complex{Float64}, NN)

    # Cálculo de las potencias
    for i in 2:NN
        PN = nodes.PGEN[i] - nodes.PLOAD[i] # Potencia activa
        QN = nodes.QGEN[i] - nodes.QLOAD[i] # Potencia reactiva
        PNE[i] += PN
        QNE[i] += QN
        SN[i] = PN + QN * 1im
    end
    
    SN = SN[2:end]
    div = conj(SN ./ VN)
    YNNINV = inv(YNN) # Inversa de YNN

    # Cálculo T
    T = YNNINV * (div - YNS * VS)
    return T
end

# Función para iterar el flujo de carga
function iterar_FFC(nodes, Ybus)
    max_iter = 20
    tol = 1e-3
    YNN = Ybus[2:end, 2:end] # Quita la primera fila y columna
    VN = ones(Complex{Float64}, size(YNN, 2)) # Vector de voltajes
    errors = Float64[]
    voltages = []

    for iter in 1:max_iter
        T = FFC(nodes, Ybus, VN)
        VN_new = T

        error = norm(VN_new - VN)
        push!(errors, error)
        push!(voltages, copy(VN_new))

        if error < tol
            println("Convergencia alcanzada en iteración $iter")
            break # Termina el bucle for prematuramente
        end

        VN = VN_new
    end

    return VN, errors, voltages 
end

# Función para calcular los promedios de ppd y pps
function promedio(pro_solar, pro_dem)
    pro_solar.Fecha = Date.(pro_solar.Fecha, DateFormat("mm/dd/yyyy"))
    ppd = Matrix{Float64}(undef, 55, 24)
    base_powerd = 1000 # Base de potencia para convertir a pu
    base_powerg = 1000000

    # Calcular ppd
    for i in 1:55
        for j in 1:24
            start_idx = (j-1)*60 + 1
            end_idx = j*60
            ppd[i, j] = mean(pro_dem[start_idx:end_idx, i]) / base_powerd
        end
    end

    # Calcular pps
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

# Función para calcular el flujo de carga diario
function flujo_carga_diario(lines, nodes, ppd, pps, dia, nodo_pgen)
    max_tensiones = Float64[]
    min_tensiones = Float64[]
    nodos_max = Int[]
    nodos_min = Int[]
    tensiones_max = []
    tensiones_min = []

    for hora in 1:24
        # Restaurar PLOAD original
        nodes.PLOAD .= PLOAD_original

        # Ajustar potencias en nodos PQ (nodos de carga)
        for (i, idx) in enumerate(pq_indices)
            nodes.PLOAD[idx] += ppd[i, hora]
            #print(nodes.PLOAD[idx])
        end

        # Ajustar PGEN en el nodo deseado
        valor = pps[dia, hora]
        ajustar_PGEN!(nodes, valor, nodo_pgen)

        # Calcular Ybus
        Ybus = calcular_b(lines, nodes)

        # Correr el flujo de carga
        VN_final, errors, voltages = iterar_FFC(nodes, Ybus)

        # Obtener tensiones finales
        tensiones = abs.(VN_final)

        # Encontrar tensiones máximas y mínimas y sus nodos
        max_tension = maximum(tensiones)
        min_tension = minimum(tensiones)
        nodo_max = argmax(tensiones)
        nodo_min = argmin(tensiones)

        push!(max_tensiones, max_tension)
        push!(min_tensiones, min_tension)
        push!(nodos_max, nodo_max)
        push!(nodos_min, nodo_min)
        push!(tensiones_max, (nodo_max, max_tension))
        push!(tensiones_min, (nodo_min, min_tension))
    end

    return max_tensiones, min_tensiones, nodos_max, nodos_min, tensiones_max, tensiones_min
end

# Cargar los datos
lines = DataFrame(CSV.File("lines.csv")) # Defino variables
nodes = DataFrame(CSV.File("nodes.csv")) # Defino variables
pro_solar = CSV.read("SolarData.csv", DataFrame)  # Reemplaza con tu archivo
pro_dem = CSV.read("Demandas.csv", DataFrame)

# Calcular ppd y pps
ppd, pps = promedio(pro_solar, pro_dem)

# Guardar el vector original PLOAD
PLOAD_original = copy(nodes.PLOAD)

# Encontrar los índices de los nodos PQ
pq_indices = findall(x -> x != 0, nodes.PLOAD)

# Elegir el día y el nodo para PGEN
dia = 100 # día
nodo_pgen = 35 # nodo a poner PGEN

# Medio da
#dia = 2 # día
#nodo_pgen = 10 # nodo a poner PGEN

# Calcular el flujo de carga diario
max_tensiones, min_tensiones, nodos_max, nodos_min, tensiones_max, tensiones_min = flujo_carga_diario(lines, nodes, ppd, pps, dia, nodo_pgen)


# Mostrar nodos y valores de tensión donde ocurren las tensiones máximas y mínimas
println("Nodos y tensiones máximas en cada hora: ", tensiones_max)
println("Nodos y tensiones mínimas en cada hora: ", tensiones_min)

# Graficar tensiones máximas y mínimas
plot(1:24, max_tensiones, label="Tensión Máxima", xlabel="Hora", ylabel="Tensión (pu)", title="Tensiones Máximas y Mínimas durante el Día", legend=:topright, grid=true)
plot!(1:24, min_tensiones, label="Tensión Mínima")