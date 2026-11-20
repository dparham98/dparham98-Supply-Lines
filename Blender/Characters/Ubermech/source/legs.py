"""Rigid lower-limb castings for the Ubermech, in metres and Blender world space."""
from math import cos, pi, sin

from mech import box, mesh, rod, shell


class Leg:
    def __init__(self, side):
        self.s = side
        self.suffix = ".L" if side == 1 else ".R"
        self.thigh = "Thigh" + self.suffix
        self.shin = "Shin" + self.suffix
        self.foot = "Foot" + self.suffix
        self.armour_width = 1.
        self.armour_depth = 1.

    def name(self, part):
        return part + self.suffix

    def axis(self, z):
        # Each armour section follows the stance of its corresponding limb.
        if z > 1.47:
            return .79 - (z-1.47)*(.14/1.09)
        if z > .48:
            return .90 - (z-.48)*(.11/.99)
        return .92

    def point(self, u, y, z):
        return (self.s*(self.axis(z)+u*self.armour_width), y*self.armour_depth, z)

    def stack(self, name, levels, mat, group, bevel=.014):
        """Eight-sided castings. Each level specifies height, half-width, front, back and chamfer."""
        rings = []
        for z, width, front, rear, c in levels:
            outline = [(-width+c,front), (width-c,front), (width,front+c),
                       (width,rear-c), (width-c,rear), (-width+c,rear),
                       (-width,rear-c), (-width,front+c)]
            xy = [self.point(u,y,z)[:2] for u,y in outline]
            if self.s < 0:
                xy.reverse()
            rings.append((z,xy))
        return shell(self.name(name),rings,mat,group,bevel)

    def casting(self, name, front, back, mat, group, bevel=.009):
        """Join two matching outlines into one closed, independently bevelled plate."""
        combined = [self.point(*p) for p in front+back]
        count = len(front)
        faces = [tuple(range(count)), tuple(reversed(range(count,2*count)))]
        for i in range(count):
            j = (i+1)%count
            faces.append((i,i+count,j+count,j))
        # The shared mesh builder orients the solid normals after mirroring.
        return mesh(self.name(name),combined,faces,mat,group,bevel)

    def shield(self, name, uz, at_y, depth, mat, group, bevel=.01):
        front = [(u,at_y(u,z),z) for u,z in uz]
        return self.casting(name,front,[(u,y+depth,z) for u,y,z in front],mat,group,bevel)

    def cheek(self, name, yz, at_u, depth, mat, group, bevel=.01):
        side = [(at_u(y,z),y,z) for y,z in yz]
        return self.casting(name,side,[(u-depth,y,z) for u,y,z in side],mat,group,bevel)

    def shaft(self,name,start,end,radius,mat,group,sides=16,bevel=.006):
        return rod(self.name(name),self.point(*start),self.point(*end),radius,mat,group,sides,bevel)

    def eyelet(self,name,u,y,z,radius,group):
        self.shaft(name+" socket",(u,y+.01,z),(u,y-.012,z),radius,"black",group,12,.001)
        self.shaft(name+" pin",(u,y-.009,z),(u,y-.018,z),radius*.55,"steel",group,6,.001)

    def upper(self):
        group = self.thigh
        self.shaft("Hip trunnion",(-.29,.018,2.53),(.28,.018,2.53),.215,"joint",group,20)
        self.stack("Femoral drive case",[(1.58,.188,-.21,.155,.068),
                   (1.74,.235,-.244,.192,.070),(2.21,.28,-.224,.246,.09),
                   (2.45,.219,-.15,.177,.062)],"graphite",group,.022)
        self.stack("Upper thigh armour",[(1.85,.245,-.255,.194,.071),
                   (1.95,.305,-.290,.230,.08),(2.26,.298,-.225,.24,.084),
                   (2.34,.228,-.16,.184,.065)],"plate",group,.019)
        # Sloping service panel and the three diagnostic light bars sit just
        # below the hip aprons. The dark frame also reads in blue team paint.
        fascia = lambda u,z: -.322+(.18*(z-1.86))
        self.shield("Thigh instrument rim",[(-.166,1.80),(.158,1.80),(.178,1.86),
                    (.131,2.126),(-.121,2.126),(-.177,1.89)],fascia,.077,"edge",group,.012)
        self.shield("Thigh instrument enamel",[(-.146,1.816),(.142,1.816),(.155,1.86),
                    (.113,2.105),(-.106,2.105),(-.154,1.895)],
                    lambda u,z:fascia(u,z)-.009,.018,"team_color",group,.006)
        self.shield("Thigh display glass",[(-.080,1.869),(.090,1.869),(.066,2.026),(-.092,2.026)],
                    lambda u,z:fascia(u,z)-.017,.012,"black",group,.005)
        for i in range(3):
            z = 1.896+.048*i
            x = -.005-.006*i
            self.shield("Thigh diagnostic %d"%(i+1),[(x-.061,z),(x+.062,z),(x+.059,z+.018),(x-.063,z+.018)],
                        lambda u,h:fascia(u,h)-.023,.009,"glow_red",group,.002)
        # The rear clevis exposes the smaller polished rods below their seals.
        self.stack("Hamstring upper clevis",[(2.252,.196,.12,.291,.032),
                   (2.294,.238,.10,.341,.042),(2.362,.202,.09,.307,.032)],
                   "graphite",group,.009)
        for k,u in enumerate((-.152,.152)):
            self.shaft("Hamstring piston %d"%k,(u,.143,1.58),(u,.277,2.29),.048,"steel",group)
            self.shaft("Hamstring sleeve %d"%k,(u,.211,1.93),(u,.273,2.34),.075,"joint",group)
            self.shaft("Hamstring wiper %d"%k,(u,.207,1.919),(u,.221,1.958),.075,"edge",group)
        self.shaft("Knee stator",(-.30,-.105,1.47),(.342,-.105,1.47),.224,"joint",group,24,.012)

    def knee(self):
        group = self.shin
        self.armour_width = 1.08
        for name,start,end,r,mat in [
                ("Knee bearing housing",.15,.320,.252,"black"),
                ("Knee journal shoulder",.305,.367,.247,"edge"),
                ("Knee hub spacer",.353,.386,.210,"joint"),
                ("Knee brake disk",.375,.413,.190,"steel"),
                ("Knee lock collar",.407,.430,.153,"black"),
                ("Knee dust cover",.421,.443,.124,"graphite")]:
            self.shaft(name,(start,-.105,1.47),(end,-.105,1.47),r*1.06,mat,group,24,.005)
        for i in range(6):
            a = 2*pi*i/6
            y,z = -.105+.172*cos(a), 1.47+.172*sin(a)
            self.shaft("Knee retainer %d"%i,(.410,y,z),(.416,y,z),.014,"joint",group,8,.001)
        self.shaft("Inboard knee journal",(-.195,-.105,1.47),(-.275,-.105,1.47),.189,"edge",group,20,.01)
        self.stack("Patella shroud",[(1.216,.212,-.274,.076,.054),
                   (1.301,.284,-.326,.132,.072),(1.665,.244,-.335,.075,.066),
                   (1.727,.194,-.263,.025,.043)],"graphite",group,.018)
        kneeface = [(-.198,1.29),(.178,1.29),(.228,1.345),(.210,1.631),
                    (.164,1.681),(-.159,1.681),(-.196,1.62),(-.227,1.36)]
        self.shield("Kneecap striking plate",kneeface,lambda u,z:-.352-.045*(z-1.29),
                    .091,"plate",group,.019)
        for k,(u,z) in enumerate([(-.151,1.353),(.15,1.353),(-.145,1.616),(.147,1.616)]):
            self.eyelet("Knee plate fixing %d"%k,u,-.355-.045*(z-1.29),z,.021,group)

    def lower(self):
        group = self.shin
        self.armour_width, self.armour_depth = 1.20, 1.10
        self.stack("Tibia load member",[(.42,.146,-.116,.108,.045),(.59,.199,-.167,.13,.046),
                   (1.10,.174,-.151,.166,.040),(1.39,.181,-.17,.1,.046)],
                   "joint",group,.017)
        self.stack("Greave lower return",[(.495,.323,-.269,.163,.073),
                   (.623,.359,-.289,.217,.095),(.704,.350,-.277,.23,.096)],
                   "joint",group,.011)
        self.stack("Greave angular casting",[(.548,.337,-.328,.200,.08),
                   (.740,.376,-.359,.237,.098),(1.143,.276,-.274,.196,.075),
                   (1.260,.228,-.216,.147,.053)],"graphite",group,.020)
        front_y = lambda u,z: -.402+.205*(z-.71)
        self.shield("Greave front strike face",[(-.194,.713),(.191,.713),(.227,.765),
                    (.176,1.156),(.126,1.206),(-.103,1.206),(-.157,1.151)],
                    front_y,.117,"plate",group,.014)
        self.shield("Greave lower lip",[(-.163,.735),(.166,.735),(.165,.774),
                    (.103,.791),(-.143,.791)],lambda u,z:front_y(u,z)-.006,.023,
                    "graphite",group,.005)
        # An offset louver and a broad team stripe break up the long flat plate.
        def louver_y(u,z):
            return front_y(u,z)-.012
        vent = [(-.124,.920),(-.047,.916),(-.030,1.112),(-.100,1.128)]
        self.shield("Greave recessed louver",vent,louver_y,.02,"black",group,.003)
        for n in range(4):
            z = .943+.043*n
            x = -.119+.005*n
            self.shield("Greave louver blade %d"%n,[(x,z),(x+.065,z-.005),
                        (x+.066,z+.007),(x+.002,z+.014)],
                        lambda u,h:louver_y(u,h)-.005,.012,"joint",group,.002)
        cheek_u = lambda y,z:.392-.205*(z-.679)
        self.cheek("Outboard greave skirt",[(-.251,.551),(.157,.616),(.246,.742),
                   (.160,1.110),(.088,1.20),(-.062,1.214),(-.175,1.094),(-.302,.742)],
                   cheek_u,.124,"plate",group,.015)
        self.cheek("Greave team chevron",[(-.234,.589),(-.127,.637),(-.055,1.071),
                   (-.085,1.171),(-.15,1.092)],lambda y,z:cheek_u(y,z)+.006,
                   .016,"team_color",group,.004)
        # A narrow return onto the front chamfer keeps the colour readable when
        # looking straight down the path of travel.
        self.shield("Greave team return",[(.224,.681),(.314,.736),(.233,1.089),(.195,1.148)],
                    lambda u,z:-.385+.194*(z-.72)+.46*(u-.225),.065,"team_color",group,.004)
        self.stack("Calf upper clevis",[(1.208,.205,.093,.363,.035),
                   (1.254,.235,.061,.391,.042),(1.30,.195,.072,.332,.037)],
                   "graphite",group,.010)
        self.shaft("Calf lower cross pin",(-.205,.153,.516),(.205,.153,.516),.069,"joint",group)
        for i,u in enumerate((-.15,.15)):
            self.shaft("Calf polished piston %d"%i,(u,.169,.521),(u,.326,1.179),.047,"steel",group)
            self.shaft("Calf actuator barrel %d"%i,(u,.259,.898),(u,.340,1.239),.075,"graphite",group)
            self.shaft("Calf seal ring %d"%i,(u,.252,.873),(u,.262,.912),.077,"edge",group,16)
        self.shaft("Lower ankle spindle",(-.228,.015,.48),(.246,.015,.48),.167,"joint",group,20,.009)

    def boots(self):
        group = self.foot
        self.armour_width, self.armour_depth = 1.15, 1.13
        self.stack("Boot heel carrier",[(.024,.318,-.325,.442,.080),
                   (.088,.362,-.337,.442,.083),(.196,.34,-.274,.398,.073),
                   (.275,.23,-.153,.292,.051)],"joint",group,.014)
        for n,(u,front,back,width,skew,top) in enumerate([
                (0.,-.652,-.092,.392,0.,.335),
                (.337,-.498,.290,.232,.040,.301),
                (-.326,-.520,.250,.207,-.025,.293)]):
            # Three discrete contact pads, set to a common sole plane. The
            # outboard toes splay around the instep and clear the moving greave.
            def pad_level(z,ww,dy,by):
                nose=front+dy
                heel=back+by
                a,b=width*ww/2, .047
                contour=[(u-a+b+skew,nose),(u+a-b+skew,nose),
                         (u+a+skew,nose+.04),(u+a,heel-.04),
                         (u+a-b,heel),(u-a+b,heel),(u-a,heel-.04),(u-a+skew,nose+.04)]
                xy=[self.point(x,y,z)[:2] for x,y in contour]
                if self.s < 0:
                    xy.reverse()
                return (z,xy)
            name = ("Centre toe","Outer toe","Inner toe")[n]
            shell(self.name(name+" tread"),[pad_level(0,1.,0,0),
                  pad_level(.062,1.014,0,0),pad_level(.085,1.,.004,-.003)],
                  "black",group,.007)
            shell(self.name(name+" casting"),[pad_level(.063,1.,.001,0),
                  pad_level(.128,1.,.009,0),pad_level(top,.78,.071,-.042)],
                  "graphite" if n!=0 else "plate",group,.010)
        # Back heel shoe is split on each side to expose the central ram.
        for i,u in enumerate((-.214,.214)):
            box(self.name("Heel tread %d"%i),self.point(u,.331,.083),(.209,.306,.166),
                "black",group,.018)
            self.stack_heel_wing(u, i)
        self.stack("Instep gaiter",[(.191,.204,-.368,.135,.065),
                   (.29,.250,-.333,.161,.069),(.441,.186,-.19,.152,.050),
                   (.48,.135,-.150,.113,.046)],"joint",group,.010)
        # Place a sloping saddle above the central toe, giving a sharp negative
        # seam underneath the upper ankle plate.
        cross = [(-.205,-.391,.299),(.205,-.391,.299),(.229,-.300,.362),
                 (.183,-.135,.457),(-.183,-.135,.457),(-.229,-.300,.362)]
        self.casting("Instep sliding tongue",cross,[(x,y,z-.054) for x,y,z in cross],"plate",group,.010)
        for n,u in enumerate((-.157,.157)):
            self.shaft("Instep fixing %d"%n,(u,-.286,.366),(u,-.291,.377),.019,
                       "steel",group,8,.002)
        # Two frontal sockets visually divide the broad central toe cap.
        for i,u in enumerate((-.108,.108)):
            pts=[(u-.016,.067),(u+.016,.067),(u+.015,.126),(u-.015,.126)]
            self.shield("Toe front drain %d"%i,pts,lambda x,z:-.655+.11*(z-.064),
                        .024,"black",group,.002)
        for name,lo,hi,r,mat in [("Ankle bearing flange",.183,.250,.181,"edge"),
                ("Ankle bearing gasket",.244,.275,.155,"black"),
                ("Ankle bolt cover",.272,.297,.121,"plate")]:
            self.shaft(name,(lo,.015,.48),(hi,.015,.48),r*1.10,mat,group,20,.006)
        self.shaft("Ankle inboard seal",(-.227,.015,.48),(-.254,.015,.48),.126,
                   "steel",group,18,.006)

    def stack_heel_wing(self, u, index):
        direction = -1 if u<0 else 1
        lower = [(u-.09,.176,.082),(u+.09,.176,.082),
                 (u+.097+direction*.057,.429,.082),(u-.097+direction*.057,.429,.082)]
        upper = [(u-.083,.189,.201),(u+.083,.189,.201),
                 (u+.072+direction*.027,.396,.215),(u-.072+direction*.027,.396,.215)]
        self.casting("Splayed heel guard %d"%index,upper,lower,"graphite",self.foot,.014)


def build():
    for side in (-1,1):
        limb = Leg(side)
        limb.upper()
        limb.knee()
        limb.lower()
        limb.boots()
