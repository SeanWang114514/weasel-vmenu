rem Customize your build environment.
rem 用相对路径，这样本地和 GitHub Actions 都能用。
if not defined BOOST_ROOT set BOOST_ROOT=%CD%\deps\boost_1_84_0
if not defined BJAM_TOOLSET set BJAM_TOOLSET=msvc-14.3