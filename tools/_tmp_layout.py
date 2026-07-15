from PIL import Image
im = Image.open('cankao/3.png').convert('RGB')
W, H = im.size
bg = (227, 205, 170)
def far(p):
    return abs(p[0]-bg[0]) + abs(p[1]-bg[1]) + abs(p[2]-bg[2]) > 100

def col_profile(y0, y1, label):
    print('---', label, 'y=%d..%d' % (y0, y1))
    for x in range(0, W, 12):
        c = sum(1 for y in range(y0, y1, 2) if far(im.getpixel((x, y))))
        if c > 3:
            print(x, c)

# scale: image 1080x1920 -> game 720x1280, divide by 1.5
col_profile(200, 360, 'TOP header')
col_profile(380, 520, 'stat-row?')
col_profile(700, 1000, 'character+slots row')
col_profile(1450, 1700, 'grid lower')
