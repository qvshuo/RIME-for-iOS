#include "RimeEngineBridge.h"

void rime_require_module_lua();
void rime_require_module_octagram();

extern "C" void rime_ios_configure_modules(RimeTraits* traits) {
  // 静态库不会自动链接只有注册副作用的对象；显式引用保留插件入口。
  rime_require_module_lua();
  rime_require_module_octagram();
  static const char* modules[] = {"default", "lua", "octagram", nullptr};
  traits->modules = modules;
}
