import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareTask, detectTasks, executeTask, youtubeExecutionStatus} from './agent.mjs';
import {youtubeProposal} from './agent-youtube.mjs';

const user='11111111-1111-4111-8111-111111111111';
const other='22222222-2222-4222-8222-222222222222';
const profile='33333333-3333-4333-8333-333333333333';
const hsid='44444444-4444-4444-8444-444444444444';
const env={HAI_API_KEY:'fixture', MEETIN_YOUTUBE_DEMO_USER_ID:user, MEETIN_YOUTUBE_PROFILE_ID:profile,
 SUPABASE_URL:'https://fixture.supabase.co', SUPABASE_SECRET_KEY:'fixture'};
const line='[00:06] FIRMIRSA (Micro · source non séparée) ·  ';
const said='Mets un commentaire « Super vidéo » sur la dernière vidéo de la chaîne H Company sur YouTube.';
const holo=draft=>async(url)=>{
 assert.equal(url,'https://api.hcompany.ai/v1/chat/completions');
 return Response.json({choices:[{message:{content:JSON.stringify(draft)}}]});
};
const commentDraft={action:'comment',target:'la dernière vidéo de la chaîne H Company',comment:'Super vidéo',quote:'Mets un commentaire « Super vidéo » sur la dernière vidéo de la chaîne H Company sur YouTube'};

test('a spoken YouTube comment becomes a signed card built from the user words', async()=>{
 const {tasks}=await detectTasks({transcript:line+said},user,env,holo(commentDraft));
 assert.equal(tasks.length,1);
 const [t]=tasks;
 assert.equal(t.action,'youtube_comment'); assert.equal(t.destination,'https://www.youtube.com');
 assert.equal(t.comment,'Super vidéo'); assert.equal(t.target,'la dernière vidéo de la chaîne H Company');
 assert.match(t.task,/« Super vidéo »/); assert.ok(t.approval);
 await assert.rejects(executeTask({approval:t.approval},user,env,()=>assert.fail()),{status:400});
});

test('no proposal for another user, without profile, without YouTube, or with invented text', async()=>{
 const fail=()=>assert.fail('Unexpected request');
 assert.equal(await youtubeProposal(said,other,env,fail),null);
 assert.equal(await youtubeProposal(said,user,{...env,MEETIN_YOUTUBE_PROFILE_ID:''},fail),null);
 assert.equal(await youtubeProposal('Lenny ajoute un test pour la page de téléchargement.',user,env,fail),null);
 assert.equal(await youtubeProposal(said,user,env,holo({...commentDraft,comment:'Bravo à toute l’équipe'})),null);
 assert.equal(await youtubeProposal(said,user,env,holo({...commentDraft,target:'une vidéo'})),null);
 assert.equal(await youtubeProposal(said,user,env,holo({...commentDraft,quote:'texte absent'})),null);
 assert.equal(await youtubeProposal(said,user,env,holo({action:null})),null);
 assert.equal(await youtubeProposal(said,user,env,async()=>new Response('down',{status:500})),null);
});

test('opening a YouTube page needs no comment and launches without claim', async()=>{
 const text='On va ouvrir la chaîne YouTube de H Company.';
 const p=await prepareTask({task:text},user,env,holo({action:'open',target:'la chaîne YouTube de H Company',quote:text.slice(0,-1)}));
 assert.equal(p.action,'youtube_open');
 let launched=0;
 const run=await executeTask({confirmed:true,approval:p.approval},user,env,async(url,options)=>{
  assert.equal(url,'https://agp.eu.hcompany.ai/api/v2/sessions'); launched++;
  const body=JSON.parse(options.body); assert.equal(body.overrides['agent.environments[kind=web].browser_profile_id'],profile);
  assert.match(body.messages,/sans rien publier/);
  return Response.json({id:hsid});
 });
 assert.equal(launched,1); assert.equal(run.sessionId,hsid);
 const status=answer=>async()=>Response.json({id:hsid,status:{status:'completed'},latest_answer:answer});
 const ok=await youtubeExecutionStatus(run,user,env,status({verified:true,outcome:'opened',account:'not logged in',page_url:'https://www.youtube.com/@HCompanyOfficial',comment:'',comment_url:''}));
 assert.deepEqual(ok,{status:'verified',pageUrl:'https://www.youtube.com/@HCompanyOfficial'});
 // Real H answer of 8 November: verified page, no outcome field.
 assert.deepEqual(await youtubeExecutionStatus(run,user,env,status({account:'FIRMIRSA',comment:'',page_url:'https://www.youtube.com/@HCompanyOfficial',verified:true,comment_url:''})),{status:'verified',pageUrl:'https://www.youtube.com/@HCompanyOfficial'});
 const stuck=await youtubeExecutionStatus(run,user,env,async()=>Response.json({id:hsid,created_at:new Date(Date.now()-240_000).toISOString(),status:{status:'running',steps:0}}));
 assert.match(stuck.message,/ne démarre pas/);
 assert.equal((await youtubeExecutionStatus(run,user,env,async()=>Response.json({id:hsid,created_at:new Date().toISOString(),status:{status:'running',steps:0}}))).status,'pending');
 const bad=await youtubeExecutionStatus(run,user,env,status({verified:true,outcome:'opened',account:'',page_url:'https://evil.example/x',comment:'',comment_url:''}));
 assert.equal(bad.status,'unverified');
});

test('a comment is claimed once per proposal and verified only when observed', async()=>{
 const p=await prepareTask({task:said},user,env,holo(commentDraft));
 const claims=new Map(); let launches=0;
 const fetcher=async(url,options)=>{
  if(url.endsWith('/rpc/meetin_claim_youtube_action')){
   const {p_proposal}=JSON.parse(options.body); const had=claims.has(p_proposal);
   if(!had) claims.set(p_proposal,null);
   return Response.json({claimed:!had,session_id:claims.get(p_proposal)});
  }
  if(url.endsWith('/rpc/meetin_save_youtube_action_session')){ const b=JSON.parse(options.body); claims.set(b.p_proposal,b.p_session); return new Response(null,{status:204}); }
  assert.equal(url,'https://agp.eu.hcompany.ai/api/v2/sessions'); launches++;
  assert.match(JSON.parse(options.body).messages,/"Super vidéo"/);
  return Response.json({id:hsid});
 };
 const results=await Promise.allSettled([executeTask({confirmed:true,approval:p.approval},user,env,fetcher),executeTask({confirmed:true,approval:p.approval},user,env,fetcher)]);
 assert.equal(launches,1); assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 const again=await executeTask({confirmed:true,approval:p.approval},user,env,fetcher);
 assert.equal(again.sessionId,hsid); assert.equal(launches,1);
 const second=await prepareTask({task:said},user,env,holo(commentDraft));
 await executeTask({confirmed:true,approval:second.approval},user,env,fetcher);
 assert.equal(launches,2);

 const status=answer=>async()=>Response.json({id:hsid,status:{status:'completed'},latest_answer:answer});
 const good={verified:true,outcome:'published',account:'@lenny',page_url:'https://www.youtube.com/watch?v=abcdefghijk',comment:'Super vidéo',comment_url:'https://www.youtube.com/watch?v=abcdefghijk&lc=Ugx123'};
 assert.deepEqual(await youtubeExecutionStatus(again,user,env,status(good)),{status:'verified',commentUrl:good.comment_url});
 assert.equal((await youtubeExecutionStatus(again,user,env,status({...good,outcome:undefined}))).status,'verified');
 for(const bad of [{comment:'Autre'},{account:'not logged in'},{verified:false},{comment_url:'https://www.youtube.com/watch?v=abcdefghijk'},{comment_url:'https://evil.example/watch?v=abcdefghijk&lc=Ugx123'}]) {
  assert.equal((await youtubeExecutionStatus(again,user,env,status({...good,...bad}))).status,'unverified');
 }
 // Real H answer of 8 November: no outcome, account "not logged in".
 const signedOut=await youtubeExecutionStatus(again,user,env,status({account:'not logged in',comment:'Super vidéo',verified:false,comment_url:''}));
 assert.match(signedOut.message,/connecté à aucun compte YouTube/);
 assert.match((await youtubeExecutionStatus(again,user,env,status({...good,verified:false,outcome:'comments_disabled'}))).message,/désactivés/);
 await assert.rejects(youtubeExecutionStatus(again,other,env,status(good)),{status:409});
 await assert.rejects(executeTask({confirmed:true,approval:p.approval},user,{...env,MEETIN_YOUTUBE_PROFILE_ID:undefined},fetcher),{status:503,code:'youtube_setup'});
});
