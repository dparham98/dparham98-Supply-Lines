"""Plated oak watchtowers for the Keep. Z is up and the public entrance faces -Y."""

from math import cos, pi, sin

from mathutils import Vector


UP = Vector((0, 0, 1))
SIDES = 8


def build_tower_shell(pb, cx, cy):
    """Add one tower to a PartBuilder whose origin is its foundation center."""
    base = Vector((cx, cy, 0))
    crown = 4.84 if cy < 0 else 5.29
    brow = crown - 0.92

    def ring(radius, z):
        # Each face looks along one cardinal or diagonal direction.
        return [base + Vector((radius * cos((i + 0.5) * 2 * pi / SIDES),
                               radius * sin((i + 0.5) * 2 * pi / SIDES), z))
                for i in range(SIDES)]

    def course(z0, r0, z1, r1, material):
        pb.add_frustum_shell(ring(r0, z0), ring(r1, z1), material)

    # Below the shoulders the joint between a replaceable oak shaft and its
    # iron shoe is visible from the street, including on the receiving side.
    course(0.31, 1.04, 0.46, 1.08, "Recessed_Steel")
    course(0.46, 1.055, 0.69, 0.93, "Satin_Silver")
    course(0.66, 0.93, brow - 0.16, 0.86, "Smoked_Oak")
    course(1.46, 0.96, 1.55, 0.965, "Recessed_Steel")
    course(brow - 0.21, 0.91, brow - 0.04, 1.01, "Recessed_Steel")
    course(brow - 0.04, 1.025, brow + 0.045, 1.00, "Satin_Silver")
    # A continuous glass strip gives the tower a human-scale observation deck.
    course(brow + 0.028, 0.94, brow + 0.45, 0.91, "Clerestory_Glass")
    course(brow + 0.40, 0.98, brow + 0.52, 1.105, "Recessed_Steel")
    course(brow + 0.52, 1.105, brow + 0.585, 1.07, "Recessed_Steel")
    course(brow + 0.585, 1.07, crown - 0.115, 0.87, "Midnight_Enamel")
    course(crown - 0.115, 0.87, crown - 0.06, 0.84, "Recessed_Steel")
    course(crown - 0.06, 0.84, crown - 0.018, 0.79, "Midnight_Enamel")
    # Form a real raised ring with an inset service hatch in the middle.
    # The two layers remain distinct in the elevated gameplay view.
    outer = ring(0.76, crown - 0.018)
    inner = ring(0.59, crown - 0.018)
    for i in range(SIDES):
        following = (i + 1) % SIDES
        bottom = [inner[i], outer[i], outer[following], inner[following]]
        pb.add_frustum_shell(bottom, [p + UP * 0.04 for p in bottom], "Recessed_Steel")
    course(crown - 0.018, 0.525, crown - 0.002, 0.514, "Midnight_Enamel")
    pb.add_box(base + Vector((0.0, 0.28, crown + 0.013)),
               (0.175, 0.067, 0.031), "Heraldic_Brass", bevel=0.012)

    # Half-braces alternate between adjacent timbers. The pointed shield
    # tongues sit high enough to reveal the ribs and their cast iron sockets.
    for face in range(SIDES):
        angle = face * 2 * pi / SIDES
        out = Vector((cos(angle), sin(angle), 0))
        right = Vector((-sin(angle), cos(angle), 0))
        handed = -1 if face % 2 else 1

        def point(u, r, z):
            return base + right * u + out * r + UP * z

        def outline(profile, near, far, material):
            pb.add_extruded_poly_frame(profile, base, right, UP, out,
                                       near, far, material)

        # Slight variations in stave colour separate the joinery at RTS zoom.
        wood = "Honey_Oak" if face % 2 == 0 else "Heart_Oak"
        pb.add_frustum_shell(
            [point(-0.245, 0.833, 0.63), point(0.225, 0.833, 0.63),
             point(0.225, 0.883, 0.63), point(-0.245, 0.883, 0.63)],
            [point(-0.23, 0.77, brow - 0.13), point(0.21, 0.77, brow - 0.13),
             point(0.21, 0.843, brow - 0.13), point(-0.23, 0.843, brow - 0.13)], wood)
        outline([(-0.31, 0.67), (-0.18, 0.67), (-0.18, 0.93),
                 (-0.235, 1.06), (-0.31, 1.06)], 0.84, 0.905, "Recessed_Steel")
        outline([(handed * -0.29, 0.94), (handed * -0.22, 0.94),
                 (handed * 0.26, 1.78), (handed * 0.18, 1.78)],
                0.877, 0.909, "Heart_Oak")
        if face % 2 == 0:
            # The iron shoe carries a pale flared greave; a slim vertical
            # reveal on either side still shows the oak below the upper shell.
            lower = [(-0.301, 0.932, 0.53), (0.301, 0.932, 0.53),
                     (0.337, 0.943, 0.64), (0.259, 0.909, 1.37),
                     (-0.259, 0.909, 1.37), (-0.337, 0.943, 0.64)]
            pb.add_frustum_shell([point(u, r - 0.060, z) for u, r, z in lower],
                                 [point(u, r, z) for u, r, z in lower], "Ivory_Armor")
        # One folded shield on each face. Its two enamel planes meet at a
        # proud central spine; the exposed backing provides a fine metal rim.
        tip = brow - (2.25 if face % 2 == 0 else 1.72)
        shoulder = brow - 0.30
        backing = [(-0.345, shoulder + 0.10), (0.345, shoulder + 0.10),
                   (0.381, shoulder - 0.04), (0.30, tip + 0.35), (0, tip),
                   (-0.30, tip + 0.35), (-0.381, shoulder - 0.04)]
        outline(backing, 0.855, 0.933, "Recessed_Steel")
        for side in (-1, 1):
            profile = [(0, 0.998, shoulder + 0.07),
                       (side * 0.31, 0.945, shoulder + 0.07),
                       (side * 0.342, 0.95, shoulder - 0.045),
                       (side * 0.266, 0.943, tip + 0.39),
                       (0, 0.971, tip + 0.07)]
            inside = [point(u, r - 0.046, z) for u, r, z in profile]
            outside = [point(u, r, z) for u, r, z in profile]
            pb.add_frustum_shell(inside, outside, "Ivory_Armor")
            stud = point(side * 0.242, 0.959, shoulder - 0.08)
            pb.add_cyl(stud, stud + out * 0.028, 0.034, 0.027, seg=6, mat="Satin_Silver")

        if face % 2 == 0 and out.x * cx + out.y * cy > 0:
            # Amber lancets on the two exposed cardinal faces of each tower.
            # Three nested shapes keep a crisp dark sill at medium distance.
            sill = tip + 0.50
            def lancet(half_width, bottom, head):
                return [(-half_width, bottom), (half_width, bottom),
                        (half_width, head - 0.185), (half_width * 0.53, head - 0.076),
                        (0, head), (-half_width * 0.53, head - 0.076),
                        (-half_width, head - 0.185)]

            outline(lancet(0.134, sill, sill + 0.97), 0.951, 1.009, "Recessed_Steel")
            outline(lancet(0.102, sill + 0.055, sill + 0.912), 1.008, 1.017, "Heraldic_Brass")
            outline(lancet(0.079, sill + 0.079, sill + 0.875), 1.016, 1.021, "Visor_Amber")
            outline([(-0.008, sill + 0.08), (0.008, sill + 0.08),
                     (0.008, sill + 0.85), (0, sill + 0.881),
                     (-0.008, sill + 0.85)], 1.020, 1.027, "Heraldic_Brass")

        # Chamfered steel posts divide the glass band at its corners. A
        # narrow sill catches the sky without painting the whole roof blue.
        pb.add_cyl(point(0.351, 0.851, brow + 0.01),
                   point(0.343, 0.823, brow + 0.45), 0.058, 0.054,
                   seg=5, mat="Recessed_Steel")
        outline([(-0.295, brow + 0.071), (0.295, brow + 0.071),
                 (0.258, brow + 0.101), (-0.258, brow + 0.101)],
                0.855, 0.885, "team_color")
        outline([(-0.27, brow + 0.306), (0.27, brow + 0.306),
                 (0.245, brow + 0.391), (-0.245, brow + 0.391)],
                0.845, 0.864, "Recessed_Steel")
        outline([(-0.22, brow + 0.321), (0.22, brow + 0.321),
                 (0.208, brow + 0.372), (-0.208, brow + 0.372)],
                0.862, 0.870, "Visor_Amber")
