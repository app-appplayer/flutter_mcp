#ifndef SECURE_STORAGE_SERVICE_H_
#define SECURE_STORAGE_SERVICE_H_

#include <windows.h>
#include <wincrypt.h>
#include <string>
#include <map>

namespace flutter_mcp {

class SecureStorageService {
 public:
  SecureStorageService();
  ~SecureStorageService();

  bool Store(const std::string& key, const std::string& value);
  bool Read(const std::string& key, std::string& value);
  bool Delete(const std::string& key);
  bool ContainsKey(const std::string& key);
  void DeleteAll();

 private:
  bool EncryptData(const std::string& plain_text, std::vector<BYTE>& encrypted_data);
  bool DecryptData(const std::vector<BYTE>& encrypted_data, std::string& plain_text);
  std::wstring GetStoragePath();
  std::wstring GetFilePath(const std::string& key);
  bool SaveToFile(const std::wstring& path, const std::vector<BYTE>& data);
  bool LoadFromFile(const std::wstring& path, std::vector<BYTE>& data);
  
  std::wstring storage_dir_;
  static constexpr const wchar_t* kStorageSubDir = L"flutter_mcp\\secure_storage";
};

}  // namespace flutter_mcp

#endif  // SECURE_STORAGE_SERVICE_H_