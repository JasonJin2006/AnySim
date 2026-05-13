using Unitful

const NM_TO_KM = 1.852
const NAUTICAL_MILE = NM_TO_KM * u"km"
const KNOT = NAUTICAL_MILE / u"hr"

nautical_miles(value::Real) = value * NAUTICAL_MILE

knots(value::Real) = value * KNOT

function voyage_duration(distance_nm::Real, speed_knots::Real)
    distance = nautical_miles(distance_nm)
    speed = knots(speed_knots)
    return uconvert(u"hr", distance / speed)
end

nautical_miles_to_km(value::Real) = float(value) * NM_TO_KM
