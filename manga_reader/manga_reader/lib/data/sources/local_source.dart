import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_page.dart';
import 'manga_source.dart';

/// Chaque dossier enfant = manga ; sous-dossier ou CBZ = chapitre.
class LocalMangaSource implements MangaSource {
  String? _root;
  void setRoot(String path) => _root = path;
  @override String get id => 'local';
  @override String get name => 'Bibliothèque locale';
  @override String get description => _root ?? 'Aucun dossier importé';
  static bool _image(String path) => const ['.jpg','.jpeg','.png','.webp','.gif'].contains(p.extension(path).toLowerCase());
  List<File> _images(Directory dir) { if (!dir.existsSync()) return []; final files=dir.listSync().whereType<File>().where((f)=>_image(f.path)).toList(); files.sort((a,b)=>a.path.toLowerCase().compareTo(b.path.toLowerCase())); return files; }
  @override Future<MangaPageResult> fetchCatalog({required int page, required CatalogQuery query}) async {
    final root=_root; if(root==null || !Directory(root).existsSync()) return const MangaPageResult([],false);
    final dirs=Directory(root).listSync().whereType<Directory>().where((d)=>p.basename(d.path).toLowerCase().contains(query.text.toLowerCase())).toList()..sort((a,b)=>a.path.compareTo(b.path));
    final all=dirs.map((d)=>Manga(id:d.path,sourceId:id,title:p.basename(d.path))).toList(); final start=(page-1)*20; if(start>=all.length)return const MangaPageResult([],false); final end=(start+20).clamp(0,all.length) as int; return MangaPageResult(all.sublist(start,end),end<all.length);
  }
  @override Future<Manga> fetchMangaDetails(Manga manga) async => manga;
  @override Future<List<Chapter>> fetchChapters(Manga manga) async {
    final dir=Directory(manga.id); if(!dir.existsSync())return [];
    final entries=dir.listSync().where((e)=>e is Directory || (e is File && p.extension(e.path).toLowerCase()=='.cbz')).toList()..sort((a,b)=>a.path.compareTo(b.path));
    return [for(var i=0;i<entries.length;i++) Chapter(id:entries[i].path,mangaId:manga.id,sourceId:id,number:'${i+1}',title:p.basenameWithoutExtension(entries[i].path),pageCount:entries[i] is Directory ? _images(Directory(entries[i].path)).length : 0)];
  }
  Future<Directory> _unzip(String filePath) async {
    final temp=await getTemporaryDirectory(); final out=Directory(p.join(temp.path,'manga_reader_cbz',p.basenameWithoutExtension(filePath)));
    if(!out.existsSync()) { final archive=ZipDecoder().decodeBytes(await File(filePath).readAsBytes()); for(final f in archive.files) { if(f.isFile && _image(f.name)) { final target=File(p.join(out.path,p.basename(f.name))); await target.parent.create(recursive:true); await target.writeAsBytes(f.content as List<int>); } } }
    return out;
  }
  @override Future<List<MangaPage>> fetchPages(Chapter chapter) async {
    final dir=chapter.id.toLowerCase().endsWith('.cbz') ? await _unzip(chapter.id) : Directory(chapter.id); final files=_images(dir);
    return [for(var i=0;i<files.length;i++) MangaPage(index:i,imageUrl:'',localPath:files[i].path,cacheKey:files[i].path)];
  }
  @override Future<List<Genre>> fetchGenres() async => const [];
}
