using Distances

function route_distance(sequence_a, sequence_b)
    a = collect(sequence_a)
    b = collect(sequence_b)
    m = length(a)
    n = length(b)
    dp = Matrix{Int}(undef, m + 1, n + 1)

    for i in 0:m
        dp[i + 1, 1] = i
    end
    for j in 0:n
        dp[1, j + 1] = j
    end

    for i in 1:m
        for j in 1:n
            cost = a[i] == b[j] ? 0 : 1
            dp[i + 1, j + 1] = min(
                dp[i, j + 1] + 1,
                dp[i + 1, j] + 1,
                dp[i, j] + cost,
            )
        end
    end

    return dp[m + 1, n + 1]
end

function coordinate_distance_km(a::Tuple{<:Real,<:Real}, b::Tuple{<:Real,<:Real})
    return evaluate(Euclidean(), collect(float.(a)), collect(float.(b)))
end
