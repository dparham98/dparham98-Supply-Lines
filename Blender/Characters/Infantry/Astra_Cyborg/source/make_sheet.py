"""Lay out three actual studio views. Run after render_studio.py with Python and Pillow."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

PREVIEW=Path(__file__).resolve().parents[1]/'preview'
PAPER=(239,236,230)
INK=(38,38,35)


def font(size):
    for face in ['C:/Windows/Fonts/bahnschrift.ttf','DejaVuSans.ttf']:
        try: return ImageFont.truetype(face,size)
        except OSError: pass
    return ImageFont.load_default(size=size)


def main():
    sheet=Image.new('RGB',(1280,1148),PAPER)
    draw=ImageDraw.Draw(sheet)
    draw.text((32,19),'SUPPLY LINES',fill=(83,82,76),font=font(16))
    draw.text((29,35),'Cyborg infantry',fill=INK,font=font(44))
    def panel(name,box,label):
        x,y,w,h=box
        with Image.open(PREVIEW/name) as frame:
            image=frame.convert('RGB')
            # Use a centred crop of empty studio canvas, preserving the full silhouette.
            aspect=w/h
            if image.width/image.height>aspect:
                dx=(image.width-image.height*aspect)*.5
                img=image.crop((round(dx),0,round(image.width-dx),image.height))
            else:
                dy=(image.height-image.width/aspect)*.5
                img=image.crop((0,round(dy),image.width,round(image.height-dy)))
            sheet.paste(img.resize((w,h),Image.Resampling.LANCZOS),(x,y))
        draw.text((x,y+h+8),label,fill=INK,font=font(19))
    panel('cyborg_infantry.png',(30,99,824,984),'Red team  /  three-quarter view')
    panel('rear.png',(869,99,380,469),'Rear  /  shoulder yoke')
    panel('blue.png',(869,615,380,468),'Blue team  /  same rig')
    sheet.save(PREVIEW/'character_sheet.png',optimize=True)


if __name__=='__main__': main()
