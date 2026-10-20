#!/usr/bin/env python3
"""Create native bundle metadata; never changes system default handlers."""
import pathlib, plistlib, shutil, sys
root=pathlib.Path(__file__).resolve().parent.parent
app=pathlib.Path(sys.argv[1]); binary=pathlib.Path(sys.argv[2]); version=(root/'VERSION').read_text().strip()
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True); (app/'Contents/Resources').mkdir(exist_ok=True)
shutil.copy2(binary,app/'Contents/MacOS/CosmicMail');shutil.copy2(root/'Resources/AppIcon.icns',app/'Contents/Resources/AppIcon.icns')
formats=[('org.songming.cosmic-mail.eml',['eml','mime'],'message/rfc822'),('com.apple.mail.emlx',['emlx'],None),('com.microsoft.outlook.msg',['msg','oft'],'application/vnd.ms-outlook'),('org.songming.cosmic-mail.mbox',['mbox','mbx','mbo'],'application/mbox')]
info=dict(CFBundleName='Cosmic Mail',CFBundleDisplayName='Cosmic Mail',CFBundleIdentifier='org.songming.CosmicMail',CFBundleExecutable='CosmicMail',CFBundlePackageType='APPL',CFBundleShortVersionString=version,CFBundleVersion=version,CFBundleIconFile='AppIcon',LSMinimumSystemVersion='14.0',LSApplicationCategoryType='public.app-category.productivity',NSHighResolutionCapable=True,NSHumanReadableCopyright='© 2026 Songming.org',CFBundleDevelopmentRegion='en',CFBundleLocalizations=['en','zh-Hans'],CFBundleURLTypes=[dict(CFBundleURLName='Email link',CFBundleURLSchemes=['mailto'],CFBundleTypeRole='Viewer',LSHandlerRank='Alternate')])
info['CFBundleDocumentTypes']=[dict(CFBundleTypeName='Email message or mailbox',CFBundleTypeExtensions=[e for _,exts,_ in formats for e in exts],LSItemContentTypes=[uti for uti,_,_ in formats]+['public.email-message','com.apple.mail.mbox'],CFBundleTypeRole='Viewer',LSHandlerRank='Alternate')]
info['UTImportedTypeDeclarations']=[]
for uti,exts,mime in formats:
    tags={'public.filename-extension':exts}
    if mime:tags['public.mime-type']=mime
    info['UTImportedTypeDeclarations'].append(dict(UTTypeIdentifier=uti,UTTypeDescription='Email message or mailbox',UTTypeConformsTo=['public.data'],UTTypeTagSpecification=tags))
with (app/'Contents/Info.plist').open('wb') as f:plistlib.dump(info,f)
