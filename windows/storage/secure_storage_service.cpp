#include "secure_storage_service.h"
#include <shlobj.h>
#include <shlwapi.h>
#include <fstream>
#include <vector>

#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "shlwapi.lib")

namespace flutter_mcp {

SecureStorageService::SecureStorageService() {
  storage_dir_ = GetStoragePath();
  
  // Create storage directory if it doesn't exist
  if (!PathFileExists(storage_dir_.c_str())) {
    SHCreateDirectoryEx(nullptr, storage_dir_.c_str(), nullptr);
  }
}

SecureStorageService::~SecureStorageService() {
}

bool SecureStorageService::Store(const std::string& key, const std::string& value) {
  std::vector<BYTE> encrypted_data;
  if (!EncryptData(value, encrypted_data)) {
    return false;
  }
  
  std::wstring file_path = GetFilePath(key);
  return SaveToFile(file_path, encrypted_data);
}

bool SecureStorageService::Read(const std::string& key, std::string& value) {
  std::wstring file_path = GetFilePath(key);
  if (!PathFileExists(file_path.c_str())) {
    return false;
  }
  
  std::vector<BYTE> encrypted_data;
  if (!LoadFromFile(file_path, encrypted_data)) {
    return false;
  }
  
  return DecryptData(encrypted_data, value);
}

bool SecureStorageService::Delete(const std::string& key) {
  std::wstring file_path = GetFilePath(key);
  if (PathFileExists(file_path.c_str())) {
    return DeleteFile(file_path.c_str()) != 0;
  }
  return true;
}

bool SecureStorageService::ContainsKey(const std::string& key) {
  std::wstring file_path = GetFilePath(key);
  return PathFileExists(file_path.c_str()) != 0;
}

void SecureStorageService::DeleteAll() {
  WIN32_FIND_DATA find_data;
  std::wstring search_path = storage_dir_ + L"\\*.dat";
  
  HANDLE find_handle = FindFirstFile(search_path.c_str(), &find_data);
  if (find_handle != INVALID_HANDLE_VALUE) {
    do {
      if (!(find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
        std::wstring file_path = storage_dir_ + L"\\" + find_data.cFileName;
        DeleteFile(file_path.c_str());
      }
    } while (FindNextFile(find_handle, &find_data));
    
    FindClose(find_handle);
  }
}

bool SecureStorageService::EncryptData(const std::string& plain_text, std::vector<BYTE>& encrypted_data) {
  DATA_BLOB data_in;
  DATA_BLOB data_out;
  
  data_in.pbData = (BYTE*)plain_text.c_str();
  data_in.cbData = plain_text.length() + 1;
  
  // Use Windows DPAPI to encrypt data
  if (CryptProtectData(&data_in, L"flutter_mcp", nullptr, nullptr, nullptr, 0, &data_out)) {
    encrypted_data.assign(data_out.pbData, data_out.pbData + data_out.cbData);
    LocalFree(data_out.pbData);
    return true;
  }
  
  return false;
}

bool SecureStorageService::DecryptData(const std::vector<BYTE>& encrypted_data, std::string& plain_text) {
  DATA_BLOB data_in;
  DATA_BLOB data_out;
  
  data_in.pbData = const_cast<BYTE*>(encrypted_data.data());
  data_in.cbData = encrypted_data.size();
  
  // Use Windows DPAPI to decrypt data
  if (CryptUnprotectData(&data_in, nullptr, nullptr, nullptr, nullptr, 0, &data_out)) {
    plain_text = std::string((char*)data_out.pbData);
    LocalFree(data_out.pbData);
    return true;
  }
  
  return false;
}

std::wstring SecureStorageService::GetStoragePath() {
  wchar_t path[MAX_PATH];
  if (SUCCEEDED(SHGetFolderPath(nullptr, CSIDL_LOCAL_APPDATA, nullptr, 0, path))) {
    std::wstring storage_path = path;
    storage_path += L"\\";
    storage_path += kStorageSubDir;
    return storage_path;
  }
  
  // Fallback to current directory
  GetCurrentDirectory(MAX_PATH, path);
  std::wstring storage_path = path;
  storage_path += L"\\";
  storage_path += kStorageSubDir;
  return storage_path;
}

std::wstring SecureStorageService::GetFilePath(const std::string& key) {
  // Simple hash to create filename
  std::hash<std::string> hasher;
  size_t hash = hasher(key);
  
  std::wstring filename = storage_dir_ + L"\\" + std::to_wstring(hash) + L".dat";
  return filename;
}

bool SecureStorageService::SaveToFile(const std::wstring& path, const std::vector<BYTE>& data) {
  std::ofstream file(path, std::ios::binary);
  if (!file) {
    return false;
  }
  
  file.write(reinterpret_cast<const char*>(data.data()), data.size());
  file.close();
  
  return file.good();
}

bool SecureStorageService::LoadFromFile(const std::wstring& path, std::vector<BYTE>& data) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file) {
    return false;
  }
  
  std::streamsize size = file.tellg();
  file.seekg(0, std::ios::beg);
  
  data.resize(size);
  file.read(reinterpret_cast<char*>(data.data()), size);
  file.close();
  
  return file.good();
}

}  // namespace flutter_mcp