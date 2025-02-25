using LinearAlgebra
using DataFrames
using CSV   
#n=100
#A=randn(n,n)
#B = randn(n)

#@time begin
#x = inv(A)*B
#end

#@time begin #Saber el tiempo computacional
#x=A\B
#end
#println("Fin")

function Matriz_B(lines,nodes)
    n = nrow(nodes)
    l = nrow(lines)
    B = zeros(n,n)
    for i in 1:l
        f = lines.FROM[i]
        t = lines.TO[i]
        yB = 1/lines.X[i]
        B[f,f] += yB
        B[t,t] += yB
        B[f,t] -= yB
        B[t,f] -= yB
    end
    B = B[2:end,2:end]
    B=inv(B)
    return B
end

# Función para crear la matriz W a partir de la matriz B
function matriz_W(B)
    n = size(B, 1) #Tamaño de la matriz B
    W = zeros(n + 1, n + 1) #Nueva matriz de ceros con una fila y columna adicionales
    W[2:end, 2:end] = B # Pasar elementos de B a W
    return W
end

# Calcular los Generation Shift Factors (GSFs)
function calculate_GSF(W, lines, nodes)
    n = nrow(nodes) #Tamaño de la matrz n (es para que recorra los 6 nodos)
    GSF = zeros(size(lines, 1), n) #(número de líneas) x (número de nodos)
    for i in 1:size(lines, 1) #Se recorre las lineas
        f = lines.FROM[i]
        t = lines.TO[i]
        
        for g in 1:n #Itera a través de cada nodo.
            
            W_ki = W[f, g] #Elemento de de W correspondiente al nodo g y el nodo de origen f.
            W_mi = W[t, g] #Elemento de de W correspondiente al nodo g y el nodo de destino t.
            GSF[i, g] = (W_ki - W_mi) / lines.X[i]

            #println("Línea: $(lines.FROM[i])-$(lines.TO[i]) | Nodo afectado: $(nodes.ID[g]) | GSF: $(GSF[i, g])")
        
        end
    end
    return GSF
end



# Función modificada para calcular los LODFs
function calculate_LODF(W, lines)
    l = size(lines, 1)
    LODF = zeros(l, l)
    for i in 1:l
        for j in 1:l
            if i != j # Ignorar la diagonal principal
                f = lines.FROM[i] #Es el "i" de la ecuación del libro (nodo de origen)
                t = lines.TO[i] #Es el "j" de la ecuación del libro (nodo de llegada)
                k = lines.FROM[j] 
                m = lines.TO[j]
                
                x_l = lines.X[i] #Línea análisis sensibilidad
                x_k = lines.X[j] #Línea desconectar
                
                num = x_k * (W[f, k] - W[f, m] - W[t, k] + W[t, m])
                denom = x_k - (W[k, k] + W[m, m] - 2 * W[k, m])
                LODF[i, j] = (num / x_l) / denom

                println("Análisis de sensibilidad: [$(f), $(t)] | Línea desconectada: [$(k), $(m)] | LODF = $(LODF[i, j])")
                #println("LODF[$i, $j] = $(LODF[i, j])")
            end
        end
    end
    return LODF
end

lines = DataFrame(CSV.File("lines.csv"))
nodes = DataFrame(CSV.File("nodes.csv"))

B = Matriz_B(lines, nodes)
W = matriz_W(B)

#println("Matriz B:")
#println(B)
#println("Matriz W:")
#println(W)

GSF = calculate_GSF(W, lines, nodes)
LODF = calculate_LODF(W, lines)
#Los Generation Shift Factors (GSFs) son coeficientes que indican cómo 
#cambiará el flujo de potencia en una línea específica debido a un cambio 
#en la generación de un nodo específico. Específicamente, un GSF para una línea i y un nodo g


#println("Generation Shift Factors (GSFs):")
#println(GSF)
