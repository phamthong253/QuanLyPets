import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bai3/pages/pets_home_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _postController = TextEditingController();

  File? _avatarImage;
  List<File> _postImages = [];

  @override
  void initState() {
    super.initState();
    _nameController.text = user?.displayName ?? "";
  }

  /// chọn avatar mới
  Future<void> _pickAvatarImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _avatarImage = File(result.files.single.path!);
      });
    }
  }

  /// upload file lên Firebase Storage
  Future<String> _uploadFile(File file, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(file);
      return await ref.getDownloadURL(); // Trả về link HTTPS
    } catch (e) {
      debugPrint("Upload error: $e");
      return "";
    }
  }

  /// cập nhật profile
  Future<void> _updateProfile() async {
    if (user == null) return;

    try {
      String? avatarUrl = user!.photoURL;

      // Nếu chọn ảnh mới → upload
      if (_avatarImage != null) {
        avatarUrl = await _uploadFile(
          _avatarImage!,
          "avatars/${user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg",
        );

        if (avatarUrl.isNotEmpty) {
          await user!.updatePhotoURL(avatarUrl);
        }
      }

      // Cập nhật tên
      if (_nameController.text.isNotEmpty) {
        await user!.updateDisplayName(_nameController.text);
      }
      // 🔥 Lưu vào Firestore (users collection)
      await FirebaseFirestore.instance.collection("users").doc(user!.uid).set({
        "name": _nameController.text,
        "avatar": avatarUrl,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // 👉 BẮT BUỘC reload user sau khi update
      await user!.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (mounted) {
        setState(() {
          _avatarImage = null; // reset ảnh local đã chọn
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Cập nhật thành công ✅")));
        // 👉 Điều hướng về PetHomeScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PetsHomeScreen()),
        );
        setState(() {}); // refresh UI
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
      }
    }
  }

  /// chọn nhiều ảnh cho bài viết
  Future<void> _pickPostImages() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _postImages = result.paths
            .whereType<String>()
            .map((p) => File(p))
            .toList();
      });
    }
  }

  /// đăng bài viết
  Future<void> _createPost() async {
    if (_postController.text.isEmpty && _postImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nội dung hoặc hình ảnh không được để trống"),
        ),
      );
      return;
    }

    try {
      List<String> imageUrls = [];
      for (var file in _postImages) {
        String url = await _uploadFile(
          file,
          "posts/${user!.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg",
        );
        imageUrls.add(url);
      }

      await FirebaseFirestore.instance.collection("posts").add({
        "uid": user!.uid,
        "name": user!.displayName ?? "Ẩn danh",
        "avatar": user!.photoURL,
        "content": _postController.text,
        "images": imageUrls,
        "likes": [],
        "createdAt": FieldValue.serverTimestamp(),
      });

      setState(() {
        _postController.clear();
        _postImages.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
      }
    }
  }

  /// like / unlike post
  Future<void> _toggleLike(DocumentSnapshot post) async {
    final data = post.data() as Map<String, dynamic>;
    final List likes = data["likes"] ?? [];
    final postRef = post.reference;

    if (likes.contains(user!.uid)) {
      await postRef.update({
        "likes": FieldValue.arrayRemove([user!.uid]),
      });
    } else {
      await postRef.update({
        "likes": FieldValue.arrayUnion([user!.uid]),
      });
    }
  }

  /// thêm bình luận
  Future<void> _addComment(DocumentSnapshot post, String text) async {
    if (text.trim().isEmpty) return;

    await post.reference.collection("comments").add({
      "uid": user!.uid,
      "name": user!.displayName ?? "Ẩn danh",
      "avatar": user!.photoURL,
      "content": text.trim(),
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  /// widget hiển thị comment
  Widget _buildComments(DocumentSnapshot post) {
    return StreamBuilder<QuerySnapshot>(
      stream: post.reference
          .collection("comments")
          .orderBy("createdAt", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final comments = snapshot.data!.docs;

        return Column(
          children: comments.map((c) {
            final data = c.data() as Map<String, dynamic>;
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: data["avatar"] != null
                    ? NetworkImage(data["avatar"])
                    : const AssetImage("assets/images/avatar.png")
                          as ImageProvider,
              ),
              title: Text(data["name"] ?? "Ẩn danh"),
              subtitle: Text(data["content"] ?? ""),
            );
          }).toList(),
        );
      },
    );
  }

  /// widget hiển thị 1 bài viết
  Widget _buildPost(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final List<dynamic> images = data["images"] ?? [];
    final List<dynamic> likes = data["likes"] ?? [];

    final TextEditingController commentCtrl = TextEditingController();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// avatar + tên
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: data["avatar"] != null
                      ? NetworkImage(data["avatar"])
                      : const AssetImage("assets/images/avatar.png")
                            as ImageProvider,
                ),
                const SizedBox(width: 8),
                Text(data["name"] ?? "Ẩn danh"),
              ],
            ),
            const SizedBox(height: 8),

            /// nội dung
            Text(data["content"] ?? ""),
            const SizedBox(height: 8),

            /// hình ảnh
            if (images.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: images
                    .map(
                      (url) => Image.network(
                        url,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    )
                    .toList(),
              ),

            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    likes.contains(user!.uid)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: likes.contains(user!.uid) ? Colors.red : null,
                  ),
                  onPressed: () => _toggleLike(doc),
                ),
                Text("${likes.length} lượt thích"),
              ],
            ),

            /// nhập bình luận
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentCtrl,
                    decoration: const InputDecoration(
                      hintText: "Viết bình luận...",
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    _addComment(doc, commentCtrl.text);
                    commentCtrl.clear();
                  },
                ),
              ],
            ),

            /// danh sách comment
            _buildComments(doc),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Trang cá nhân")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            /// avatar + tên
            GestureDetector(
              onTap: _pickAvatarImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _avatarImage != null
                    ? FileImage(_avatarImage!) // ảnh mới chọn local
                    : (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                    ? NetworkImage(user!.photoURL!) // ảnh đã lưu trên Firebase
                    : null, // mặc định ko có ảnh
                child:
                    (_avatarImage == null &&
                        (user?.photoURL == null || user!.photoURL!.isEmpty))
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Tên hiển thị"),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _updateProfile,
              child: const Text("Cập nhật"),
            ),
            const Divider(height: 32),

            /// tạo bài viết
            TextField(
              controller: _postController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "Bạn đang nghĩ gì?",
                border: OutlineInputBorder(),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _postImages.map((file) {
                return Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Image.file(
                      file,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _postImages.remove(file)),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: _pickPostImages,
                  icon: const Icon(Icons.photo_library),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _createPost,
                  child: const Text("Đăng bài"),
                ),
              ],
            ),
            const Divider(height: 32),

            /// danh sách bài viết
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("posts")
                  .orderBy("createdAt", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final posts = snapshot.data!.docs;
                return Column(
                  children: posts.map((doc) => _buildPost(doc)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
