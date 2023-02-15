using LinearAlgebra
using Graphs, SimpleWeightedGraphs, Cairo, Compose, Fontconfig, Colors
#using MetaGraphs, GraphRecipes, Plots
using GraphPlot

const COLORS = [colorant"red", colorant"blue", colorant"green", colorant"yellow", colorant"orange", colorant"purple", colorant"tan", colorant"pink", colorant"cyan", colorant"silver"]


function Read_data(path)

    """ String -> Dict{String : Float}

        path : Le nom du fichier a extraire sans le / a la fin en incluant son extention

        Retourne un dictionnaire representant les donnees de path.
    """

    data = Dict()
    nend = false

    open(string("./PRP_instances/", path)) do f
        for line in readlines(f)[2:end]
            tline = split(line, " ")

            if length(tline) == 2 && !nend
                data[tline[1]] = Int(parse(Float64, tline[2]))
            elseif "h" in tline
                if tline[1] == "0"
                    data["x"] = []
                    data["y"] = []
                    data["h"] = []
                    data["L"] = []
                    data["L0"] = []
                end

                push!(data["x"], Int(parse(Float64, tline[2])))
                push!(data["y"], Int(parse(Float64, tline[3])))
                push!(data["h"], Int(parse(Float64, tline[6])))
                push!(data["L"], Int(parse(Float64, tline[8])))
                push!(data["L0"], Int(parse(Float64, tline[10])))
            elseif tline[1] == "d"
                nend = true
                data["d"] = []
                continue
            elseif nend
                d = map(x -> parse(Int, x), tline[2:end - 1])
                push!(data["d"], d)
            end
        end
    end

    d = data["d"]
    n = data["n"]
    l = data["l"]
    md = zeros(Int64, n, l)

    for i in 1:n
        for t in 1:l
            md[i, t] = d[i][t]
        end
    end

    data["d"] = md

    return data
end


function Distance_A(data, i, j)

    """ Dict{String : Float} * Int * Int -> Float

        data : Les donnees extraits d'une instance PRP (cf. function Read_data).
        i : Le sommet de individu i en supposant que les indices vont de 1 à n + 1 (1 fournisseur n revendeurs)

        Retourne la distance de type A de i a j.
    """

    x = data["x"]
    y = data["y"]

    return floor(sqrt(((x[i] - x[j]) ^ 2) + ((y[i] - y[j]) ^ 2)) + 1 / 2)
end


function Distance_B(data, i, j)

    """ Dict{String : Float} * Int * Int -> Float

        data : Les donnees extraits d'une instance PRP (cf. function Read_data).
        i : Le sommet de individu i en supposant que les indices vont de 1 à n + 1 (1 fournisseur n revendeurs)
        j : Le sommet de individu j en supposant que les indices vont de 1 à n + 1 (1 fournisseur n revendeurs)

        Retourne la distance de type B de i a j.
    """

    x = data["x"]
    y = data["y"]
    mc = data["mc"]

    return mc * sqrt(((x[i] - x[j]) ^ 2) + ((y[i] - y[j]) ^ 2))
end


function Initialize_SC(data, type)

    """ Dict{String : Float} * String -> Matrix{Float}

        data : Les donnees extraits d'une instance PRP (cf. function Read_data).
        type : Le type d'instance "A" ou "B".

        Retourne une Matrice representant les couts de distances heuristiques de type type pour data.
    """

    n = data["n"]
    l = data["l"]
    res = zeros(Float64, n, l)

    for i in 1:n
        for t in 1:l
            if type == "A"
                res[i, t] = Distance_A(data, 1, i + 1) + Distance_A(data, i + 1, 1)
            elseif type == "B"
                res[i, t] = Distance_B(data, 1, i + 1) + Distance_B(data, i + 1, 1)
            end
        end
    end

    return res
end


function Update_SC(data, type, vrp)

    """ Dict{String : Float} * String * Array[Tuple(Int, Int)] -> Matrix{Float}

        data : Les donnees extraits d'une instance PRP (cf. function read_data).
        type : Le type d'instance "A" ou "B".
        vrp : Une liste d'arcs representant une tournee realisable (cf. function Vrp_local dans vrp.jl)

        Retourne la matrice des couts heuristiques mise a jour par vrp.
    """

    n = data["n"]
    l = data["l"]
    res = zeros(Float64, n, l)

    for i in 1:n
        for t in 1:l
            e = -1
            s = -1

            for (l, k) in vrp[t]
                if l == i
                    s = k
                elseif k == i
                    e = l
                end
            end

            if e == -1 && s == -1
                continue
            end

            if type == "A"
                res[i, t] = Distance_A(data, e + 1, i + 1) + Distance_A(data, i + 1, s + 1) - Distance_A(data, e + 1, s + 1)
            elseif type == "B"
                res[i, t] = Distance_B(data, e + 1, i + 1) + Distance_B(data, i + 1, s + 1) - Distance_B(data, e + 1, s + 1)
            end
        end
    end

    return res
end


function Draw_vrp(path, data, vrp, tp, opts, root_name = "Results")

    """ String * Dict{String : Float} * Array[Tuple(Int, Int)] * Int * String * String -> Void

        path : Le nom du fichier a etudier sans le / a la fin et en incluant son extention (.prp).
        data : Les donnees extraits d'une instance PRP (cf. function Read_data).
        vrp : Une liste d'arcs representant une tournee realisable de la periode tp (cf. function Vrp_local dans vrp.jl)
        tp : La periode etudiee
        opts : Le nom de la methode utilisee (heu ou exact)
        root_name : Le nom du dossier ou placer ces resultats.

        Dessine le vrp de la periode tp sous forme de graphe.
    """

    n = data["n"] + 1
    g = SimpleDiGraph(n)
    xvrp = copy(vrp)
    t = []
    f = true
    r = -1
    Ncg = []

    for (i, j) in vrp
        if i + 1 != 1 && !(i + 1 in Ncg)
            push!(Ncg, i + 1)
        elseif j + 1 != 1 && !(j + 1 in Ncg)
            push!(Ncg, j + 1)
        end
    end

    while f
        f = false
        mt = [0]

        for (i, j) in xvrp
            if i == 0
                push!(mt, j)
                deleteat!(xvrp, findall(x -> x == (i, j), xvrp))
                f = true
                break
            end
        end

        if f
            while mt[end] != 0
                for (i, j) in xvrp
                    if i == mt[end]
                        push!(mt, j)
                        break
                    end
                end
            end

        push!(t, mt)
        end
    end

    #println(t)

    for tr in t
        for i in 1:length(tr) - 1
            add_edge!(g, tr[i] + 1, tr[i + 1] + 1)
        end
    end

    ecolors = []

    for e in edges(g)
        ent = src(e)
        sor = dst(e)

        for i in 1:length(t)
            for j in 1:length(t[i]) - 1
                if t[i][j] + 1 == ent && t[i][j + 1] + 1 == sor
                    push!(ecolors, COLORS[i])
                end
            end
        end
    end

    tx = [x for x in data["x"]]
    ty = [y for y in data["y"]]
    nodec = [colorant"turquoise" for i in 1:n + 1]
    nodec[1] = colorant"yellow"

    for k in Ncg
        nodec[k] = colorant"orange"
    end

    if !ispath(string("./", root_name))
        mkdir(string("./", root_name))
    end

    if !ispath(string("./", root_name, "/", opts))
        mkdir(string("./", root_name, "/", opts))
    end

    testname = split(path, ".")
    file = string("PDI_", opts)

    if !ispath(string("./", root_name, "/", opts, "/", file, "_", testname[1]))
        mkdir(string("./", root_name, "/", opts, "/", file,  "_", testname[1]))
    end

    draw(PDF(string("./", root_name, "/", opts, "/", file, "_", testname[1], "/", "VRP_", opts, "_", testname[1], "_", "p", tp, ".pdf"), 16cm, 16cm), gplot(g, tx, ty, nodelabel = 1:nv(g), edgestrokec = ecolors, nodefillc = nodec))

    return
end


function Detect_subtour(vrp)
    xvrp = copy(vrp)
    t = []
    f = true
    r = -1
    res = []

    while f
        f = false
        mt = [0]

        for (i, j) in xvrp
            if i == 0
                push!(mt, j)
                deleteat!(xvrp, findall(x -> x == (i, j), xvrp))
                f = true
                break
            end
        end

        if f
            while mt[end] != 0
                for (i, j) in xvrp
                    if i == mt[end]
                        push!(mt, j)
                        deleteat!(xvrp, findall(x -> x == (i, j), xvrp))
                        break
                    end
                end
            end

        push!(t, mt)
        end
    end


    while length(xvrp) != 0
        i, j = xvrp[1]
        vt = [i]
        f = false

        while !f
            xvrp2 = copy(xvrp)

            for (i, j) in xvrp2
                if i == vt[end]
                    push!(vt, j)
                    deleteat!(xvrp, findall(x -> x == (i, j), xvrp))
                end

                if vt[1] == vt[end]
                    f = true
                    break
                end
            end
        end

        #if vt[1] == 0
        #    vt = vt[2:end]
        #end

        push!(res, vt)
    end

    return t, res
end
