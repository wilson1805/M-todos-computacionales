using CSV, DataFrames, Statistics, Plots, Clustering

# Cargar los datos del archivo CSV
solar_data = DataFrame(CSV.File("SolarData.csv"))

# Crear una matriz para almacenar los promedios por hora
pps = Matrix{Float64}(undef, 365, 24)

# Calcular el promedio de potencia para cada hora del día
for day in 1:365
    for hour in 1:24
        start_idx = (day - 1) * 24 * 12 + (hour - 1) * 12 + 1
        end_idx = start_idx + 11
        if end_idx <= size(solar_data, 1)
            pps[day, hour] = mean(solar_data.Potencia[start_idx:end_idx])
        else
            pps[day, hour] = NaN
        end
    end
end

#println("Cantidad de NaN en pps: ", sum(isnan.(pps)))
println("Tamaño de pps antes de kmeans: ", size(pps))  # Debería ser (365, 24)

# Aplicar K-Means sobre las filas (días), agrupando en 3 clusters
k = 3
result = kmeans(pps', k)  # Se usa pps directamente sin transponer
println("Tamaño de result.centers: ", size(result.centers))  # Debería ser (3, 24)
clusters = result.assignments
centroids = result.centers'  # Matriz 3 × 24 (3 casos × 24 horas)
println("Tamaño de centroids: ", size(centroids))  # Debería ser (3, 24)


# Ordenar los centroides de menor a mayor generación promedio
sorted_indices = sortperm([mean(centroids[i, :]) for i in 1:k])
sorted_centroids = centroids[sorted_indices, :]

# Graficar los casos obtenidos
plot(1:24, sorted_centroids[1, :], lw=2, label="Mínima Generación", color=:blue)
plot!(1:24, sorted_centroids[2, :], lw=2, label="Generación Promedio", color=:green)
plot!(1:24, sorted_centroids[3, :], lw=2, label="Máxima Generación", color=:red)

xlabel!("Hora del día")
ylabel!("Potencia (kW)")
title!("Casos de Generación Solar")
savefig("Casos_estudio.png")
#legend()
#grid!(true)

