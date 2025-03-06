using CSV, DataFrames, Statistics, Dates, Plots

# Cargar el DataFrame de Demandas
pro_dem = CSV.read("Demandas.csv", DataFrame)
sd = DataFrame(CSV.File("SolarData.csv"))

# Crear una matriz para almacenar los promedios por hora
ppd = Matrix{Float64}(undef, 55, 24)

# Iterar sobre cada nodo (columna)
for i in 1:55
    # Iterar sobre cada hora (24 horas)
    for j in 1:24
        # Calcular el promedio de los 60 minutos correspondientes a esa hora
        start_idx = (j-1)*60 + 1
        end_idx = j*60
        ppd[i, j] = mean(pro_dem[start_idx:end_idx, i])
    end
end

# Función para graficar la potencia demandada por hora y por minuto de un nodo específico
function graficar_potencia_nodo(pro_dem, nodo)
    # Graficar potencia demandada por hora
    horas = 1:24
    potencia_hora = ppd[nodo, :]
    plot(horas, potencia_hora, label="Potencia por Hora", xlabel="Hora", ylabel="Potencia", title="Potencia Demandada por Hora - Nodo $nodo", legend=:topright, grid=true)

    # Graficar potencia demandada por minuto
    minutos = 1:size(pro_dem, 1)
    potencia_minuto = pro_dem[!, nodo]
    plot(minutos, potencia_minuto, label="Potencia por Minuto", xlabel="Minuto", ylabel="Potencia", title="Potencia Demandada por Minuto - Nodo $nodo", legend=:topright, grid=true)
end

# Seleccionar el nodo
nodo = 50 

# Graficar la potencia demandada por hora y por minuto del nodo seleccionado
graficar_potencia_nodo(pro_dem, nodo)

