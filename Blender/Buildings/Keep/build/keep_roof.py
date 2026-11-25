"""The Keep's standing-seam hall roof and timber receiving canopy, in metres."""
from mathutils import Matrix, Vector


Z = Vector((0, 0, 1))
X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
FACES = (-Y, X, Y, -X)


def _ring(radius, height):
    return [Vector((sx * radius, sy * radius, height))
            for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]


def _beam(part, start, end, width, thickness, across, material):
    """Place rectangular wood stock or a raised seam between two points."""
    start, end = Vector(start), Vector(end)
    axis = (end - start).normalized()
    normal = axis.cross(across).normalized()
    lateral = normal.cross(axis)
    rotation = Matrix((lateral, normal, axis)).transposed().to_4x4()
    part.add_box((end + start) * .5, (width, thickness, (end - start).length),
                 material, rot=rotation)


def _standing_seams(part, outer, inner, bottom, top, spacing):
    """Cut straight seams where they reach a hip instead of fanning the panels."""
    for outward in FACES:
        side = Z.cross(outward)
        corners = (outward + side) * outer + Z * bottom, (outward + side) * inner + Z * top
        _beam(part, *corners, .105, .071, outward - side, "Recessed_Steel")
        side_count = int((outer - .16) / spacing)
        for index in range(-side_count, side_count + 1):
            offset = index * spacing
            upper_radius = max(inner, abs(offset) + .09)
            fraction = (outer - upper_radius) / (outer - inner)
            start = outward * outer + side * offset + Z * (bottom + .021)
            end = outward * upper_radius + side * offset + Z * (bottom + fraction * (top - bottom) + .021)
            _beam(part, start, end, .044, .053, side, "Midnight_Enamel")


def build_roof_shell(rf):
    # One uninterrupted iron roof spans the hall. A continuous timber and
    # glazed lantern lifts the eaves, admitting daylight under the deep hip.
    layers = [
        (3.52, 4.36, 3.54, 4.43, "Heart_Oak"),
        (3.47, 4.43, 3.47, 4.91, "Honey_Oak"),
        (3.54, 4.91, 3.58, 4.98, "Smoked_Oak"),
        (3.62, 4.98, 3.62, 5.055, "Recessed_Steel"),
        (3.62, 5.055, 1.72, 6.88, "Royal_Enamel"),
        (1.75, 6.88, 1.70, 6.98, "Recessed_Steel"),
    ]
    for outer, bottom, inner, top, material in layers:
        rf.add_frustum_shell(_ring(outer, bottom), _ring(inner, top), material)
    _standing_seams(rf, 3.62, 1.72, 5.055, 6.88, .54)

    lancet = [(-.345, 0), (.345, 0), (.332, .19), (.27, .30),
              (.14, .405), (0, .479), (-.14, .405), (-.27, .30), (-.332, .19)]
    for outward in FACES:
        side = Z.cross(outward)
        for index in range(-4, 5):
            sill = outward * 3.47 + side * (index * .755) + Z * 4.435
            rf.add_extruded_poly_frame(lancet, sill, side, Z, outward, -.005, .027, "Recessed_Steel")
            pane = [(u * .876, v * .878 + .018) for u, v in lancet]
            rf.add_extruded_poly_frame(pane, sill, side, Z, outward, .027, .04, "Clerestory_Glass")
            # Amber interior light shines along the base below the broad glazing.
            glow = [(-.254, .046), (.254, .046), (.254, .128), (-.254, .128)]
            rf.add_extruded_poly_frame(glow, sill, side, Z, outward, .04, .044, "Visor_Amber")
            _beam(rf, sill + outward * .052 + Z * .020,
                  sill + outward * .052 + Z * .443,
                  .034, .031, side, "Recessed_Steel")


def add_bay_canopy(rb):
    """Open-sided machine-folded roof with laminated oak knees at its ends."""
    inner, outer, half = -3.17, -4.78, 2.49
    inner_z, outer_z = 3.33, 2.75
    deck = [Vector((inner, -half, inner_z)), Vector((outer, -half, outer_z)),
            Vector((outer, half, outer_z)), Vector((inner, half, inner_z))]
    rb.add_frustum_shell(deck, [p + Z * .075 for p in deck], "Royal_Enamel")
    for index in range(-4, 5):
        y = index * .55
        _beam(rb, (inner, y, inner_z + .089), (outer, y, outer_z + .089),
              .05, .055, Y, "Midnight_Enamel")

    rb.add_box((outer, 0, outer_z - .008), (.09, half * 2 + .05, .135), "Recessed_Steel")
    rb.add_box((outer + .09, 0, outer_z - .085), (.12, half * 2, .11), "Heart_Oak")
    rb.add_box((inner, 0, inner_z), (.13, half * 2, .16), "Recessed_Steel")
    for side in (-1, 1):
        y = side * 2.05
        # Concave, tapered glulam knee. Two timber laminations and an iron
        # pin can be read from the gate or from a cart approaching the porch.
        top_edge = [(-4.72, 2.06), (-4.56, 2.32), (-4.34, 2.57),
                    (-4.04, 2.78), (-3.70, 2.98), (-3.23, 3.17)]
        bottom_edge = [(-4.72, 1.86), (-4.46, 2.22), (-4.24, 2.46),
                       (-3.96, 2.68), (-3.61, 2.87), (-3.23, 3.02)]
        rb.add_extruded_poly_frame(top_edge + list(reversed(bottom_edge)),
                                   Vector((0, y, 0)), X, Z, Y, -.085, .085, "Heart_Oak")
        seam = [(x * .45 + bx * .55, z * .45 + bz * .55)
                for (x, z), (bx, bz) in zip(top_edge, bottom_edge)]
        midline = seam + [(x, z - .015) for x, z in reversed(seam)]
        rb.add_extruded_poly_frame(midline, Vector((0, y, 0)), X, Z, Y,
                                   -.087, .087, "Honey_Oak")
        _beam(rb, (outer, y, outer_z - .08), (inner, y, inner_z - .08),
              .19, .13, Y, "Heart_Oak")
        rb.add_cyl((-4.65, y - .105, 2.06), (-4.65, y + .105, 2.06),
                   .055, seg=8, mat="Satin_Silver")
