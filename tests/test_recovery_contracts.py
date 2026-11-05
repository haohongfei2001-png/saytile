"""Synthetic, executable contract tests; no production audio or app input."""
from pathlib import Path
import json, sqlite3, sys, tempfile, unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from model.reference_store import Store, ContractError, utf16_length

class Contracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='saytile-contracts-')
        self.root = Path(self.tmp.name)
        self.store = Store(self.root/'store.sqlite',self.root/'audio')
        self.store.db.execute("INSERT INTO capture_sessions(id,started_at,device_uid,sample_rate,content_generation) VALUES ('s','demo','synthetic',16000,1)")
        self.add_record('u1',0,100,'你好')
        self.add_revision('u1','edit1','用户修改稿','user_edit')
        self.store.db.execute("UPDATE utterances SET preferred_revision_id='edit1' WHERE id='u1'")
        self.add_record('u2',100,200,'下一段')
        self.add_chunk('c1',0,100,['u1'])
    def tearDown(self):
        self.store.close(); self.tmp.cleanup()
    def add_record(self, uid,start,end,text):
        self.store.db.execute('''INSERT INTO utterances(id,session_id,group_id,core_start_sample,core_end_sample,context_start_sample,content_generation)
            VALUES (?,'s','g',?,?,?,1)''',(uid,start,end,start))
        self.add_revision(uid,'r'+uid,text)
    def add_revision(self, uid,rid,text,origin='asr_final'):
        self.store.db.execute('''INSERT INTO transcript_revisions(id,utterance_id,revision_no,origin,text,created_at) VALUES (?,?,1,?,?,'demo')''',(rid,uid,origin,text))
        return rid
    def add_chunk(self,cid,start,end,ids):
        self.store.audio_path(cid+'.pcm').write_bytes(b'\x12\x34'*(end-start))
        self.store.db.execute('''INSERT INTO audio_chunks(id,session_id,ordinal,relative_path,first_sample,durable_frames,final_frames,state)
            VALUES (?,'s',?,?,?, ?,?,'sealed')''',(cid,self.val('SELECT count(*) FROM audio_chunks'),cid+'.pcm',start,end-start,end-start))
        for uid in ids:
            u=self.store.db.execute('SELECT core_start_sample,core_end_sample FROM utterances WHERE id=?',(uid,)).fetchone()
            self.store.db.execute("INSERT INTO utterance_audio_refs VALUES (?,?,'core',?,?)",(uid,cid,max(start,u[0]),min(end,u[1])))
    def add_job(self,uid='u1',jid='j1',state='running'):
        self.store.db.execute('''INSERT INTO recognition_jobs(id,utterance_id,engine,model_revision,source_generation,state,active_attempt)
            VALUES (?,?,'synthetic','test',1,?,'a1')''',(jid,uid,state))
    def reopen(self):
        self.store.close(); self.store=Store(self.root/'store.sqlite',self.root/'audio')
    def val(self,sql,args=()): return self.store.db.execute(sql,args).fetchone()[0]
    def binding(self): return self.store.bind_target('Synthetic editor; not a real OS target')

    def test_audio_delete_keeps_all_text_versions_and_preference(self):
        before=[tuple(r) for r in self.store.db.execute("SELECT * FROM transcript_revisions WHERE utterance_id='u1'")]
        self.store.request_audio_erasure('u1')
        self.assertEqual(before,[tuple(r) for r in self.store.db.execute("SELECT * FROM transcript_revisions WHERE utterance_id='u1'")])
        self.assertEqual(self.val("SELECT preferred_revision_id FROM utterances WHERE id='u1'"),'edit1')
    def test_audio_delete_keeps_search_and_copy_content(self):
        iid=self.store.request_audio_erasure('u1'); self.store.cleanup_audio(iid)
        self.assertIn('用户修改稿',self.store.search('修改'))
        self.assertEqual(self.val("SELECT text FROM transcript_revisions WHERE id='ru1'"),'你好')
    def test_audio_delete_does_not_advance_content_generation(self):
        self.store.request_audio_erasure('u1')
        self.assertEqual(self.val("SELECT value FROM store_meta WHERE key='content_generation'"),'1')
        self.assertEqual(self.val('SELECT count(*) FROM deletion_tombstones'),0)
    def test_audio_delete_cancels_jobs_and_rejects_late_callback(self):
        self.add_job(); self.store.request_audio_erasure('u1')
        self.assertFalse(self.store.accept_asr('j1','a1','不应该复活'))
        self.assertEqual(self.val("SELECT state FROM recognition_jobs WHERE id='j1'"),'cancelled')
    def test_audio_delete_does_not_cancel_other_utterance(self):
        self.add_job('u2','j2'); self.store.request_audio_erasure('u1')
        self.assertTrue(self.store.accept_asr('j2','a1','另一段正常完成'))
    def test_delete_intent_survives_restart_before_unlink(self):
        iid=self.store.request_audio_erasure('u1'); self.reopen()
        self.assertEqual(self.val("SELECT audio_state FROM utterances WHERE id='u1'"),'delete_pending')
        self.assertTrue(self.store.audio_path('c1.pcm').exists())
        self.assertTrue(self.store.cleanup_audio(iid))
    def test_cleanup_after_unlink_before_commit_is_retryable(self):
        iid=self.store.request_audio_erasure('u1')
        with self.assertRaises(OSError): self.store.cleanup_audio(iid,fail_after_unlink=True)
        self.reopen()
        self.assertFalse(self.store.audio_path('c1.pcm').exists())
        self.assertTrue(self.store.cleanup_audio(iid))
        self.assertIn('用户修改稿',self.store.search('用户'))
    def test_shared_chunk_defers_and_preserves_other_audio(self):
        self.add_chunk('shared',0,200,['u1','u2'])
        iid=self.store.request_audio_erasure('u1')
        self.assertFalse(self.store.cleanup_audio(iid))
        self.assertTrue(self.store.audio_path('shared.pcm').exists())
        self.assertEqual(self.val("SELECT state FROM audio_erasure_chunks WHERE chunk_id='shared'"),'shared_deferred')
    def test_shared_chunk_cleanup_when_all_references_deleted(self):
        self.add_chunk('shared',0,200,['u1','u2'])
        one=self.store.request_audio_erasure('u1'); self.store.cleanup_audio(one)
        two=self.store.request_audio_erasure('u2'); self.assertTrue(self.store.cleanup_audio(two))
        self.assertEqual(self.val('SELECT count(*) FROM audio_erasure_intents WHERE state="complete"'),2)
        self.assertFalse(self.store.audio_path('shared.pcm').exists())
    def test_active_audio_lease_delays_physical_cleanup(self):
        self.store.db.execute("INSERT INTO audio_leases VALUES ('lease','c1','player')")
        iid=self.store.request_audio_erasure('u1'); self.assertFalse(self.store.cleanup_audio(iid))
        self.store.db.execute('DELETE FROM audio_leases')
        self.assertTrue(self.store.cleanup_audio(iid))
    def test_orphan_recovery_subtracts_audio_tombstone_not_text(self):
        self.store.request_audio_erasure('u1'); self.reopen()
        self.assertEqual(self.store.recoverable_audio_ranges(1,'s',0,200),[(100,200)])
        self.assertIn('你好',self.store.search('你好'))
    def test_stale_generation_not_recovered(self):
        self.assertEqual(self.store.recoverable_audio_ranges(0,'s',0,200),[])
    def test_retention_protects_pinned_audio(self):
        self.store.db.execute("UPDATE utterances SET is_pinned=1 WHERE id='u1'")
        with self.assertRaises(ContractError): self.store.request_audio_erasure('u1',reason='retention')
        self.assertEqual(self.val('SELECT count(*) FROM audio_erasure_intents'),0)
    def test_retention_protects_pending_or_failed_asr(self):
        self.add_job(state='retry_wait')
        with self.assertRaises(ContractError): self.store.request_audio_erasure('u1',reason='retention')
    def test_retention_allows_completed_unpinned_audio(self):
        self.add_job(state='completed')
        iid=self.store.request_audio_erasure('u1',reason='retention')
        self.assertTrue(self.store.cleanup_audio(iid))
    def test_user_can_explicitly_delete_pinned_audio(self):
        self.store.db.execute("UPDATE utterances SET is_pinned=1 WHERE id='u1'")
        self.assertTrue(self.store.cleanup_audio(self.store.request_audio_erasure('u1')))
    def test_active_utterance_requires_sealing_before_delete(self):
        self.store.db.execute("UPDATE utterances SET core_end_sample=NULL WHERE id='u1'")
        with self.assertRaises(ContractError): self.store.request_audio_erasure('u1')
    def test_repeated_audio_deletion_is_idempotent(self):
        self.assertEqual(self.store.request_audio_erasure('u1'),self.store.request_audio_erasure('u1'))
    def test_unlink_path_cannot_escape_audio_root(self):
        self.store.db.execute("UPDATE audio_chunks SET relative_path='../other.txt' WHERE id='c1'")
        iid=self.store.request_audio_erasure('u1')
        with self.assertRaises(ContractError): self.store.cleanup_audio(iid)
        self.assertEqual(self.val('SELECT state FROM audio_erasure_intents'),'pending')
    def test_first_dispatch_and_incremental_suffix(self):
        b=self.binding(); one=self.store.reserve_direct(b,'u1','ru1',2)
        r=self.add_revision('u1','rplus','你好，世界')
        two=self.store.reserve_direct(b,'u1',r,5)
        self.assertEqual([one['text'],two['text']],['你好','，世界'])
    def test_new_revision_same_prefix_does_not_repeat(self):
        b=self.binding(); self.store.reserve_direct(b,'u1','ru1',2)
        r=self.add_revision('u1','rsame','你好')
        self.assertIsNone(self.store.reserve_direct(b,'u1',r,2))
        self.assertEqual(self.val('SELECT count(*) FROM insertion_operations'),1)
    def test_changed_prefix_pauses_without_dispatch(self):
        b=self.binding(); self.store.reserve_direct(b,'u1','ru1',2)
        r=self.add_revision('u1','rchange','你们好')
        with self.assertRaises(ContractError): self.store.reserve_direct(b,'u1',r,3)
        self.assertEqual(self.val('SELECT state FROM input_bindings WHERE id=?',(b,)),'review')
        self.assertEqual(self.val('SELECT count(*) FROM insertion_operations'),1)
    def test_stable_range_cannot_shrink(self):
        b=self.binding(); self.store.reserve_direct(b,'u1','ru1',2)
        with self.assertRaises(ContractError): self.store.reserve_direct(b,'u1','ru1',1)
    def test_volatile_suffix_not_sent(self):
        b=self.binding(); r=self.add_revision('u1','rpartial','你好还不稳定','asr_partial')
        self.assertEqual(self.store.reserve_direct(b,'u1',r,2)['text'],'你好')
    def test_utf16_chinese_and_nonbmp_emoji(self):
        b=self.binding(); r=self.add_revision('u1','remoji','你😀好')
        self.assertEqual(utf16_length('你😀'),3)
        self.assertEqual(self.store.reserve_direct(b,'u1',r,3)['text'],'你😀')
        self.assertEqual(self.store.reserve_direct(b,'u1',r,4)['text'],'好')
    def test_invalid_utf16_boundary_rolls_back(self):
        b=self.binding(); r=self.add_revision('u1','remoji','你😀好')
        with self.assertRaises(ContractError): self.store.reserve_direct(b,'u1',r,2)
        self.assertEqual(self.val('SELECT count(*) FROM insertion_operations'),0)
        self.assertEqual(self.val('SELECT count(*) FROM dispatch_cursors'),0)
    def test_out_of_range_and_negative_offsets_rejected(self):
        b=self.binding()
        for end in [-1,3,True]:
            with self.assertRaises(ContractError): self.store.reserve_direct(b,'u1','ru1',end)
    def test_uncertain_dispatch_does_not_block_next_utterance(self):
        b=self.binding(); op=self.store.reserve_direct(b,'u1','ru1',2)
        self.store.mark_dispatch(op['id'],'unverified')
        self.assertEqual(self.store.reserve_direct(b,'u2','ru2',3)['text'],'下一段')
    def test_restart_marks_uncertain_and_invalidates_binding(self):
        b=self.binding(); op=self.store.reserve_direct(b,'u1','ru1',2); self.reopen()
        self.assertEqual(self.val('SELECT state FROM insertion_operations WHERE id=?',(op['id'],)),'unverified')
        with self.assertRaises(ContractError): self.store.reserve_direct(b,'u1','ru1',2)
        self.assertEqual(self.val('SELECT count(*) FROM insertion_operations'),1)
    def test_explicit_rebind_has_new_identity(self):
        old=self.binding(); self.store.invalidate_binding(old); new=self.binding()
        self.assertNotEqual(old,new)
        with self.assertRaises(ContractError): self.store.reserve_direct(old,'u1','ru1',2)
        self.assertEqual(self.store.reserve_direct(new,'u2','ru2',3)['text'],'下一段')
    def test_text_revision_is_immutable_after_dispatch(self):
        b=self.binding(); self.store.reserve_direct(b,'u1','ru1',2)
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.db.execute("UPDATE transcript_revisions SET text='覆盖' WHERE id='ru1'")
    def test_audio_deletion_does_not_prevent_text_insertion(self):
        iid=self.store.request_audio_erasure('u1'); self.store.cleanup_audio(iid)
        self.assertEqual(self.store.reserve_direct(self.binding(),'u1','ru1',2)['text'],'你好')
    def test_search_treats_like_wildcards_as_literals(self):
        self.assertEqual(self.store.search('%'),[])
        self.assertEqual(self.store.search('_'),[])
    def test_cursor_cannot_rewind_by_sql(self):
        b=self.binding(); self.store.reserve_direct(b,'u1','ru1',2)
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.db.execute('UPDATE dispatch_cursors SET dispatched_utf16_end=0 WHERE binding_id=?',(b,))
    def test_restart_cancels_prepared_operations(self):
        self.store.db.execute("INSERT INTO insertion_operations(id,utterance_id,revision_id,text_start,text_end,state,created_at) VALUES ('prepared','u1','ru1',0,2,'prepared','demo')")
        self.reopen()
        self.assertEqual(self.val("SELECT state FROM insertion_operations WHERE id='prepared'"),'cancelled')
    def test_restart_releases_dead_process_audio_leases(self):
        self.store.db.execute("INSERT INTO audio_leases VALUES ('lease','c1','dead-player')")
        iid=self.store.request_audio_erasure('u1')
        self.assertFalse(self.store.cleanup_audio(iid))
        self.reopen()
        self.assertTrue(self.store.cleanup_audio(iid))
    def test_foreign_keys_and_schema_version(self):
        self.assertEqual(self.val('PRAGMA user_version'),2)
        self.assertEqual(self.store.db.execute('PRAGMA foreign_key_check').fetchall(),[])

if __name__=='__main__':
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(Contracts)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    report={'scope':'Synthetic SQLite/filesystem design contract tests; no macOS integration',
            'total':result.testsRun,'passed':result.testsRun-len(result.failures)-len(result.errors),
            'failures':[(str(t),s) for t,s in result.failures],
            'errors':[(str(t),s) for t,s in result.errors]}
    (ROOT/'evidence/rebuilt-contracts.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    sys.exit(not result.wasSuccessful())
