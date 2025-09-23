// profile_page.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:bai3/pages/pets_home_screen.dart';
import 'package:bai3/pages/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final User? user = FirebaseAuth.instance.currentUser;

  File? _avatarImage;
  String? avatarUrl;
  String? name;
  String? username;
  String? userId;
  String? email;
  String? phone;
  String? gender;
  String? birthday;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user!.uid)
          .get();
      final data = doc.data();

      setState(() {
        avatarUrl = data?["avatar"] ?? user!.photoURL;
        name = data?["name"] ?? user!.displayName ?? "";
        username = data?["username"] ?? (user!.email?.split("@")[0] ?? "");
        userId = data?["userId"] ?? user!.uid;
        email = data?["email"] ?? user!.email;
        phone = data?["phone"] ?? "";
        gender = data?["gender"] ?? "";
        birthday = data?["birthday"] ?? "";
      });
    } catch (e) {
      debugPrint("Load profile error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Lỗi tải profile: $e")));
      }
    }
  }

  /// pick avatar local
  Future<void> _pickAvatarImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _avatarImage = File(result.files.single.path!);
        });
      }
    } catch (e) {
      debugPrint("Pick avatar error: $e");
    }
  }

  /// upload file lên Firebase Storage, trả về downloadURL hoặc "" nếu lỗi
  Future<String> _uploadFile(File file, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      if (snapshot.state == TaskState.success) {
        final url = await ref.getDownloadURL();
        debugPrint("Upload success: $url");
        return url;
      } else {
        debugPrint("Upload not success, state: ${snapshot.state}");
        return "";
      }
    } catch (e) {
      debugPrint("Upload error: $e");
      return "";
    }
  }

  /// cập nhật toàn bộ profile (upload avatar nếu có + lưu Firestore + update Auth name/photo)
  Future<void> _updateProfile() async {
    if (user == null) return;

    try {
      String newAvatarUrl = avatarUrl ?? "";

      // upload avatar nếu có
      if (_avatarImage != null) {
        newAvatarUrl = await _uploadFile(
          _avatarImage!,
          "avatars/${user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg",
        );
        if (newAvatarUrl.isNotEmpty) {
          try {
            await user!.updatePhotoURL(newAvatarUrl);
          } catch (e) {
            debugPrint("updatePhotoURL error: $e");
          }
        }
      }

      // update displayName on Auth if changed
      if (name != null && name!.isNotEmpty) {
        try {
          await user!.updateDisplayName(name);
        } catch (e) {
          debugPrint("updateDisplayName error: $e");
        }
      }

      // lưu vào Firestore
      await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
        "name": name ?? "",
        "username": username ?? "",
        "avatar": newAvatarUrl,
        "email": email ?? user!.email,
        "userId": userId ?? user!.uid,
        "phone": phone ?? "",
        "gender": gender ?? "",
        "birthday": birthday ?? "",
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // reload auth user to reflect changes locally
      try {
        await user!.reload();
      } catch (_) {}

      if (mounted) {
        setState(() {
          avatarUrl = newAvatarUrl;
          _avatarImage = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Cập nhật thành công ✅")));
      }
    } catch (e) {
      debugPrint("Update profile error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Lỗi cập nhật: $e")));
      }
    }
  }

  /// Lưu một field đơn lẻ vào Firestore (và update Auth nếu field là name)
  Future<void> _saveFieldToFirestore(String fieldName, dynamic value) async {
    if (user == null) return;
    try {
      // Nếu sửa name thì update FirebaseAuth displayName luôn
      if (fieldName == 'name') {
        try {
          await user!.updateDisplayName(value?.toString() ?? "");
        } catch (e) {
          debugPrint("updateDisplayName error: $e");
        }
      }
      await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
        fieldName: value,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // reload user to sync
      try {
        await user!.reload();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Đã lưu")));
      }
    } catch (e) {
      debugPrint("Save single field error: $e");
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Lỗi lưu: $e")));
    }
  }

  /// dialog chung để edit text field; onSavedLocal cập nhật UI, saveToFirestore nếu true thì lưu ngay
  Future<void> _showEditDialog({
    required String title,
    required String initialValue,
    required ValueChanged<String> onSavedLocal,
    String firestoreField = '',
    bool saveToFirestore = false,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) async {
    final controller = TextEditingController(text: initialValue);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Chỉnh sửa $title'),
          content: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(hintText: hint ?? 'Nhập $title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = controller.text.trim();
                onSavedLocal(val);
                Navigator.pop(context);
                if (saveToFirestore && firestoreField.isNotEmpty) {
                  await _saveFieldToFirestore(firestoreField, val);
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  /// gender dialog (chọn option)
  Future<void> _showGenderDialog() async {
    final options = ['Male', 'Female', 'Other', 'Prefer not to say'];
    String? selected = gender;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Chọn giới tính'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              return RadioListTile<String>(
                title: Text(opt),
                value: opt,
                groupValue: selected,
                onChanged: (v) {
                  selected = v;
                  setState(() {});
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                setState(() => gender = selected ?? "");
                Navigator.pop(context);
                await _saveFieldToFirestore('gender', gender ?? "");
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  /// pick date of birth with date picker, save to Firestore immediately
  Future<void> _pickDateOfBirth() async {
    DateTime initial = DateTime.now().subtract(const Duration(days: 365 * 20));
    if (birthday != null && birthday!.isNotEmpty) {
      try {
        final parts = birthday!.split('/');
        if (parts.length == 3) {
          final d = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          final y = int.parse(parts[2]);
          initial = DateTime(y, m, d);
        }
      } catch (_) {}
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final formatted =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      setState(() => birthday = formatted);
      await _saveFieldToFirestore('birthday', birthday);
    }
  }

  Widget _buildInfoRow(String title, String? value, VoidCallback onTap) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        value ?? "",
        style: const TextStyle(color: Colors.black87),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Avatar
            GestureDetector(
              onTap: _pickAvatarImage,
              child: CircleAvatar(
                radius: 56,
                backgroundImage: _avatarImage != null
                    ? FileImage(_avatarImage!)
                    : (avatarUrl != null && avatarUrl!.isNotEmpty)
                    ? NetworkImage(avatarUrl!)
                    : const AssetImage("assets/images/default_avatar.png")
                          as ImageProvider,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickAvatarImage,
              icon: const Icon(Icons.photo_camera),
              label: const Text("Change Profile Picture"),
            ),
            const SizedBox(height: 16),

            // Profile Information
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Profile Information",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildInfoRow("Name", name, () {
                    _showEditDialog(
                      title: 'Name',
                      initialValue: name ?? "",
                      onSavedLocal: (v) => setState(() => name = v),
                      firestoreField: 'name',
                      saveToFirestore: true,
                    );
                  }),
                  const Divider(height: 1),
                  _buildInfoRow("Username", username, () {
                    _showEditDialog(
                      title: 'Username',
                      initialValue: username ?? "",
                      onSavedLocal: (v) => setState(() => username = v),
                      firestoreField: 'username',
                      saveToFirestore: true,
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Personal Information
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Personal Information",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildInfoRow("User ID", userId, () {
                    // copy id
                    if (userId != null && userId!.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: userId!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Copied ID")),
                      );
                    }
                  }),
                  const Divider(height: 1),
                  _buildInfoRow("E-mail", email, () {}),
                  const Divider(height: 1),
                  _buildInfoRow("Phone Number", phone, () {
                    _showEditDialog(
                      title: 'Phone Number',
                      initialValue: phone ?? "",
                      onSavedLocal: (v) => setState(() => phone = v),
                      firestoreField: 'phone',
                      saveToFirestore: true,
                      keyboardType: TextInputType.phone,
                    );
                  }),
                  const Divider(height: 1),
                  _buildInfoRow("Gender", gender, () {
                    _showGenderDialog();
                  }),
                  const Divider(height: 1),
                  _buildInfoRow("Date of Birth", birthday, () {
                    _pickDateOfBirth();
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            TextButton(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(),
                    ), // hoặc màn hình login
                  );
                }
              },
              child: const Text(
                "Logout Account",
                style: TextStyle(color: Colors.red),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _updateProfile();

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const PetsHomeScreen()),
            );
          }
        },
        child: const Icon(Icons.save),
      ),
    );
  }
}
