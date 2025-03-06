using CSV, DataFrames, Statistics, Plots

# Cargar los datos del archivo CSV
solar_data = DataFrame(CSV.File("SolarData.csv"))

# Crear una matriz para almacenar los promedios por hora
pps = Matrix{Float64}(undef, 365, 24)

# Iterar sobre cada día (365 días)
for day in 1:365
    # Iterar sobre cada hora (24 horas)
    for hour in 1:24
        # Calcular el promedio de los 12 datos correspondientes a esa hora
        start_idx = (day - 1) * 24 * 12 + (hour - 1) * 12 + 1
        end_idx = start_idx + 11
        pps[day, hour] = mean(solar_data.Potencia[start_idx:end_idx])
    end
end

highlight_day = 150

# Crear el primer gráfico con todas las curvas en gris
plo1 = plot(pps', xlabel="Hora del día", ylabel="Potencia (kW)", title="Potencia solar por hora", legend=false, grid=true, color=:gray, alpha=0.5)

# Añadir la curva resaltada en rojo al gráfico existente
plot!(plo1, 1:24, pps[highlight_day, :], color=:red, linewidth=2)

# Mostrar el gráfico combinado
display(plo1)
