#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project after adding/moving Swift files."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]
objects={}
def uid(value):return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def ref(key):return uid(key)
def obj(key,isa,**fields):objects[uid(key)]={'isa':isa,**fields};return uid(key)
def encode(value):
 if isinstance(value,dict):return '{ '+ ' '.join(f'{encode(k)} = {encode(v)};' for k,v in value.items())+' }'
 if isinstance(value,list):return '( '+', '.join(encode(x) for x in value)+', )' if value else '()'
 return json.dumps(str(value))
app=ref('target-app');unit=ref('target-unit');ui=ref('target-ui');project=ref('project')
productRefs=[];fileRefs=[];phaseRefs={}
for kind,name,folder,productType in [('app','Rescue','Rescue','com.apple.product-type.application'),('unit','RescueTests','Tests/RescueCoreTests','com.apple.product-type.bundle.unit-test'),('ui','RescueUITests','Tests/RescueUITests','com.apple.product-type.bundle.ui-testing')]:
 files=sorted((root/folder).rglob('*.swift'))
 if kind=='app':files=sorted((root/'Sources/RescueCore').glob('*.swift'))+files
 builds=[]
 for file in files:
  path=str(file.relative_to(root));f=obj('file-'+path,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=path,sourceTree='<group>');fileRefs.append(f)
  builds.append(obj('build-'+kind+path,'PBXBuildFile',fileRef=f))
 source=obj('sources-'+kind,'PBXSourcesBuildPhase',buildActionMask='2147483647',files=builds,runOnlyForDeploymentPostprocessing='0')
 resources=[]
 if kind=='app':
  f=obj('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Rescue/Resources/Assets.xcassets',sourceTree='<group>');fileRefs.append(f)
  resources.append(obj('build-assets','PBXBuildFile',fileRef=f))
 phase=obj('resources-'+kind,'PBXResourcesBuildPhase',buildActionMask='2147483647',files=resources,runOnlyForDeploymentPostprocessing='0')
 framework=obj('frameworks-'+kind,'PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
 ext='app' if kind=='app' else 'xctest'
 product=obj('product-'+kind,'PBXFileReference',explicitFileType='wrapper.application' if kind=='app' else 'wrapper.cfbundle',includeInIndex='0',path=name+'.'+ext,sourceTree='BUILT_PRODUCTS_DIR');productRefs.append(product)
 configs=[]
 for configuration in ['Debug','Release']:
  settings={'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.mhacks.rescue'+('' if kind=='app' else '.'+kind),'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1','GENERATE_INFOPLIST_FILE':'YES','CODE_SIGN_STYLE':'Automatic','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if configuration=='Debug' else '-O','ENABLE_TESTABILITY':'YES' if configuration=='Debug' else 'NO','SWIFT_EMIT_LOC_STRINGS':'YES','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks']}
  if kind=='app':settings.update({'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor','CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]':'Rescue/Resources/Simulator.entitlements','INFOPLIST_FILE':'Rescue/Resources/Info.plist','INFOPLIST_KEY_CFBundleDisplayName':'Gusto','INFOPLIST_KEY_LSApplicationCategoryType':'public.app-category.food-and-drink','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UISupportedInterfaceOrientations':'UIInterfaceOrientationPortrait','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if configuration=='Debug' else ''})
  elif kind=='unit':settings.update({'TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Rescue.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Rescue','BUNDLE_LOADER':'$(TEST_HOST)'})
  else:settings['TEST_TARGET_NAME']='Rescue'
  configs.append(obj('config-'+kind+configuration,'XCBuildConfiguration',buildSettings=settings,name=configuration))
 configlist=obj('configs-'+kind,'XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
 dependencies=[]
 if kind!='app':
  proxy=obj('proxy-'+kind,'PBXContainerItemProxy',containerPortal=project,proxyType='1',remoteGlobalIDString=app,remoteInfo='Rescue')
  dependencies=[obj('dependency-'+kind,'PBXTargetDependency',target=app,targetProxy=proxy)]
 obj('target-'+kind,'PBXNativeTarget',buildConfigurationList=configlist,buildPhases=[source,framework,phase],buildRules=[],dependencies=dependencies,name=name,productName=name,productReference=product,productType=productType)
for path in ['DESIGN.md','ARCHITECTURE.md','AGENTS.md','README.md']:
 fileRefs.append(obj('doc-'+path,'PBXFileReference',lastKnownFileType='net.daringfireball.markdown',path=path,sourceTree='<group>'))
products=obj('products','PBXGroup',children=productRefs,name='Products',sourceTree='<group>')
group=obj('root-group','PBXGroup',children=fileRefs+[products],sourceTree='<group>')
configs=[]
for configuration in ['Debug','Release']:
 configs.append(obj('project-config-'+configuration,'XCBuildConfiguration',buildSettings={'SDKROOT':'iphoneos','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','DEBUG_INFORMATION_FORMAT':'dwarf' if configuration=='Debug' else 'dwarf-with-dsym','GCC_C_LANGUAGE_STANDARD':'gnu17','GCC_PREPROCESSOR_DEFINITIONS':['DEBUG=1','$(inherited)'] if configuration=='Debug' else ['$(inherited)'],'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0'},name=configuration))
configlist=obj('project-configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
obj('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'1640','TargetAttributes':{app:{'CreatedOnToolsVersion':'16.4'},unit:{'CreatedOnToolsVersion':'16.4','TestTargetID':app},ui:{'CreatedOnToolsVersion':'16.4','TestTargetID':app}}},buildConfigurationList=configlist,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,unit,ui])
projectDir=root/'Rescue.xcodeproj';projectDir.mkdir(exist_ok=True)
(projectDir/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project})+'\n')
schemes=projectDir/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def buildref(id,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Rescue.xcodeproj"/>'
appref=buildref(app,'Rescue.app')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildref(unit,'RescueTests.xctest')}</TestableReference><TestableReference skipped="NO">{buildref(ui,'RescueUITests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(schemes/'Rescue.xcscheme').write_text(scheme)
print('Generated Rescue.xcodeproj with',len(fileRefs),'file references')
