# Randnet Server Content Manifest
# Extracted from DDDiskR-DRDJ0-0.ndd (V0) and NUD-DRDJ01-JPN.ndd (V1)

## CATEGORY 1: Preserved server-side cached content
### Source: peach.randnet.ne.jp/help/
These pages were cached FROM the original Randnet server onto the disk.
They must be served by Tomcat at: /help/ 
Files: peach_help/

## CATEGORY 2: ROM browser UI pages  
### Source: x-avefront://---.nixon_screen/html/ (local browser)
These are embedded in the disk ROM and served locally by the browser engine.
They must be served by Tomcat at the paths the 64DD expects.
Files: ui_pages/

## CATEGORY 3: Server-side content NOT cached (must be recreated)
### www.randnet.ne.jp/v/BR0000x/ pages:
- BR00002/ - メンバー情報の変更 (member info change form - links via ChangeMemberPW servlet)
- BR00003/ - ランドキャッシュ情報 (Rand Cash balance info)
- BR00005/ - クレジットなどのお支払い (credit/payment info)
- BR00006/ - ザブーン リンクス (web links/bookmarks page)
- BR00007/ - ニュース (Randnet news) 
- BR00008/ - ランドネットご利用ガイド (usage guide/help)
- BR00009/ - DDファン (V1 only - 64DD fan content)
- BR00010/ - GETモール (V1 only - GET shopping mall)
- BR00011/ - NETザブーン (V1 only - NET Zaboon links)

### www.randnetdd.co.jp:
- /hello/ - Default home page shown on connection
- /main.html - Main Randnet DD portal page

## DESIGN SYSTEM (confirmed from both disks and manual)
- Outer body background: #000000 (black)
- Settings page body: #555555 (dark grey)  
- Header bars: #99CC33 (green)
- Content cells: #FFFFCC (cream)
- Highlight cells: #FFFF99 (yellow)
- Label cells: #FFCC66 (orange)
- White text on headers: #FFFFFF
- Content width: 482px
- Header height: 36px with 28x28 icon + white text
- Font: default (Shift-JIS)
- All images served from x-avefront://---.nixon_screen/image/ (local)
- External server pages use same colour scheme

## IMAGE LIST (all referenced in ROM)
Local images (served from x-avefront - embedded in disk ROM):
- r_white_ur.gif, r_white_wave.gif, r_randnetlogo.gif, r_white_dr.gif
- r_2000.gif (year 2000 logo)
- r_b_news.gif (news button 201x47px)
- r_b_help.gif (help button)
- r_b_mail.gif (mail button) 
- r_minibutton.gif
- r_logo_dd.gif (DDファン logo 170x60px)
- r_logo_get.gif (GETモール logo 170x60px)
- r_logo_net.gif (NETザブーン logo 170x60px)
- r_3_round.gif
- icon1.gif (40x28px - used in SAMPLE pages)
- arrow.gif (20x20px - list arrow)
- arrow-b.gif
- dl_randnetdd.gif (28x28px - blue disk icon)
- dl_hand.gif (28x28px - hand/error icon)
- dl_spana.gif (28x28px - mail/wrench icon)
- dl_batsu.gif (28x28px - X/error icon)
- dl_question.gif (28x28px - question mark icon)
- dl_yen.gif (28x28px - yen/bank icon)
- randb.gif (40x28px - Rand Bank icon)
- defpi.gif, corrupt.gif, delayed.gif (mail state icons)

Line-check area images (x-avefront://---.nixon_sub/line-check/):
- top_logo.gif (137x46px - Randnet logo)
- top_arrow.gif (20x20px)
- top_hr.gif (2x104px - vertical divider)
- top_goriyou.gif (141x80px - usage guide button)
- top_logos.gif (69x23px - small logo)

## TEMPLATE PLACEHOLDERS (must be substituted by server)
- !replace_member_id! - member ID
- !replace_member_pw! - member password  
- !replace_dial_out! - outside line number
- !replace_dial_type0! - tone dial checked state
- !replace_dial_type1! - pulse dial checked state
- !replace_tone_checked! - tone radio button checked
- !replace_pulse_checked! - pulse radio button checked
- !replace_outsideno_value! - outside number value
- !replace_addno_value! - additional number
- <!replace_aplist!> - AP (access point) list
- !replace_5_checked!, !replace_10_checked!, !replace_15_checked! - auto-disconnect time
- !replace_un5_1_passcheckmethod! - current PW check method text
- !replace_un5_1_accesslimitation! - current access limitation text
- <!replace_un7_1_src_mail_address!> - mail address display
