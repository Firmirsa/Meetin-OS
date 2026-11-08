import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareTask, detectTasks, executeTask, youtubeExecutionStatus} from './agent.mjs';
import {youtubeProposal} from './agent-youtube.mjs';
const user='11111111-1111-4111-8111-111111111111';
const sid='22222222-2222-4222-8222-222222222222';
const env={HAI_API_KEY:'fixture', MEETIN_YOUTUBE_DEMO_USER_ID:user, MEETIN_YOUTUBE_PROFILE_ID:sid,
 SUPABASE_URL:'https://fixture.supabase.co', SUPABASE_SECRET_KEY:'fixture'};
const transcript='Il faut commenter une vidéo YouTube de H Company avec Bravo !';
const denied=()=>assert.fail('Unexpected external request');
test('explicit demo proposal is source-backed, owner-bound, signed and requires confirmation',async()=>{
 const {tasks}=await detectTasks({transcript},user,env,denied);
 assert.equal(tasks.length,1); assert.equal(tasks[0].comment,'Bravo !');
 assert.ok(transcript.includes(tasks[0].quote));
 await assert.rejects(executeTask({approval:tasks[0].approval},user,env,denied),{status:400});
 await assert.rejects(executeTask({confirmed:true,approval:tasks[0].approval},sid,env,denied),{status:409});
 const [payload,sig]=tasks[0].approval.split('.'); const forged=JSON.parse(Buffer.from(payload,'base64url'));
 forged.channel='@Other';
 await assert.rejects(executeTask({confirmed:true,approval:Buffer.from(JSON.stringify(forged)).toString('base64url')+'.'+sig},user,env,denied),{status:409});
 assert.equal(youtubeProposal(transcript,sid,env),null);
 assert.ok(youtubeProposal('[00:04] Vous · '+transcript,user,env));
 for(const source of ['Il ne faut pas commenter une vidéo YouTube de H Company avec Bravo', 'On pourrait commenter une vidéo YouTube de H Company avec Bravo', 'Il faut commenter une vidéo YouTube de H Company sans écrire Bravo']) assert.equal(youtubeProposal(source,user,env),null);
 await assert.rejects(executeTask({confirmed:true,approval:tasks[0].approval},user,{...env,MEETIN_YOUTUBE_PROFILE_ID:undefined},denied),{status:503,code:'youtube_setup'});
});
test('persistent claim prevents concurrent or regenerated proposals from posting twice',async()=>{
 let claimed=false, stored=null, launches=0;
 const fetcher=async(url,options)=>{
  if(url.endsWith('meetin_claim_youtube_demo')) { if(claimed)return Response.json({claimed:false,session_id:stored}); claimed=true; return Response.json({claimed:true}); }
  if(url.endsWith('meetin_save_youtube_session')) { stored=sid; return new Response(null,{status:204}); }
  assert.equal(url,'https://agp.eu.hcompany.ai/api/v2/sessions'); launches++;
  const request=JSON.parse(options.body);
  assert.equal(request.overrides['agent.environments[kind=web].browser_profile_id'],sid);
  assert.match(request.messages,/UNE SEULE FOIS/); assert.equal(request.agent,'h/web-surfer-pro');
  return Response.json({id:sid});
 };
 const p=await prepareTask({task:transcript},user,env,denied);
 const results=await Promise.allSettled([executeTask({confirmed:true,approval:p.approval},user,env,fetcher),executeTask({confirmed:true,approval:p.approval},user,env,fetcher)]);
 assert.equal(launches,1); assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 const second=await prepareTask({task:transcript},user,env,denied);
 const run=await executeTask({confirmed:true,approval:second.approval},user,env,fetcher);
 assert.equal(run.sessionId,sid); assert.equal(launches,1);
 const status=answer=>async()=>Response.json({id:sid,status:{status:'completed',outcome:'success'},latest_answer:answer});
 const blocked=await youtubeExecutionStatus(run,user,env,status({outcome:'comments_disabled'}));
 assert.equal(blocked.status,'unverified'); assert.match(blocked.message,/désactivés/);
 const answer={verified:true,outcome:'published',channel:'@HCompanyOfficial',account:'@Fraawdrinn',comment:'Bravo !',comment_url:'https://www.youtube.com/watch?v=abcdefghijk&lc=Ugx123'};
 assert.equal((await youtubeExecutionStatus(run,user,env,status(answer))).status,'verified');
 for(const bad of [{account:'@Other'},{channel:'@Other'},{comment:'Other'},{comment_url:'https://evil.example/watch?v=abcdefghijk&lc=Ugx123'},{comment_url:'https://www.youtube.com/watch?v=abcdefghijk'}]) assert.equal((await youtubeExecutionStatus(run,user,env,status({...answer,...bad}))).status,'unverified');
});
