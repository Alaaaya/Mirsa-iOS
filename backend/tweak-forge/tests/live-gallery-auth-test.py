from audit import *
import urllib.request,urllib.error,json,uuid,secrets,hashlib,datetime
keys={k['name']:k['api_key'] for k in api('/api-keys?reveal=true')}
SR=keys.get('service_role'); AN=keys.get('anon')
base='https://'+P+'.supabase.co'
def call(url,data=None,hdr={},method=None):
    r=urllib.request.Request(url,data=json.dumps(data).encode() if data is not None else None,headers={'Content-Type':'application/json',**hdr},method=method)
    try:
        x=urllib.request.urlopen(r);return x.status,json.loads(x.read() or b'null')
    except urllib.error.HTTPError as e:
        try:b=json.loads(e.read())
        except:b=None
        return e.code,b
def mkuser():
    em='galtest-'+uuid.uuid4().hex[:8]+'@example.invalid';pw=secrets.token_urlsafe(16)
    s,u=call(base+'/auth/v1/admin/users',{'email':em,'password':pw,'email_confirm':True},{'apikey':SR,'Authorization':'Bearer '+SR})
    s,t=call(base+'/auth/v1/token?grant_type=password',{'email':em,'password':pw},{'apikey':AN})
    return u['id'],t['access_token']
def F(tok,dev,body):
    if body['action']=='gallery': return call(base+'/functions/v1/mirsa-forge?action=gallery',None,{'apikey':AN,'Authorization':'Bearer '+tok,'x-mirsa-device':dev},'GET')
    return call(base+'/functions/v1/mirsa-forge',body,{'apikey':AN,'Authorization':'Bearer '+tok,'x-mirsa-device':dev})
def mkcode(ttl):
    c='-'.join(''.join(secrets.choice('ABCDEFGHJKMNPQRSTUVWXYZ23456789') for _ in range(4)) for _ in range(4))
    h=hashlib.sha256(('mirsa-admin-v1|'+c).encode()).hexdigest()
    q("insert into mirsa_forge_admin_codes(code_hash,expires_at) values ('%s', now() + interval '%s')"%(h,ttl));return c
uA,tA=mkuser();uB,tB=mkuser();uC,tC=mkuser()
dA,dA2,dB,dC=[str(uuid.uuid4()) for _ in range(4)]
res={}
good='%hook UIView\n- (void)layoutSubviews { %orig; }\n%end'
s,r=F(tA,dA,{'action':'publish','name':'GalTest','bundleID':'com.test.app','description':'d','code':good,'settings':[]});res['publish']=s
gid=q("select id from mirsa_forge_gallery where name='GalTest' and user_id='%s'"%uA)[0]['id']
res['row_bound']=q("select owner_device from mirsa_forge_gallery where id='%s'"%gid)[0]['owner_device']==dA
res['list_mine_A']=[i.get('mine') for i in F(tA,dA,{'action':'gallery'})[1]['items'] if i['id']==gid]
res['list_mine_A_otherdev']=[i.get('mine') for i in F(tA,dA2,{'action':'gallery'})[1]['items'] if i['id']==gid]
res['list_mine_B']=[i.get('mine') for i in F(tB,dB,{'action':'gallery'})[1]['items'] if i['id']==gid]
res['leak']=any('user_id' in i or 'owner_device' in i for i in F(tA,dA,{'action':'gallery'})[1]['items'])
res['B_update_404']=F(tB,dB,{'action':'gallery-update','id':gid,'name':'Hack'})[0]
res['A_otherdev_update_404']=F(tA,dA2,{'action':'gallery-update','id':gid,'name':'Hack'})[0]
res['B_delete_404']=F(tB,dB,{'action':'gallery-delete','id':gid})[0]
res['spoof_admin_body_404']=F(tB,dB,{'action':'gallery-update','id':gid,'name':'Hack','admin':True,'user_id':uA,'owner_device':dB})[0]
res['unauth']=call(base+'/functions/v1/mirsa-forge',{'action':'gallery-delete','id':gid},{'apikey':AN})[0]
res['A_update_200']=F(tA,dA,{'action':'gallery-update','id':gid,'name':'GalTest2','code':good})[0]
res['A_unsafe_422']=F(tA,dA,{'action':'gallery-update','id':gid,'code':'system("id");'})[0]
res['name_after']=q("select name from mirsa_forge_gallery where id='%s'"%gid)[0]['name']
# claim
res['claim_wrong']=F(tB,dB,{'action':'admin-claim','code':'ABCD-EFGH-JKMN-PQRS'})[0]
exp=mkcode('-1 minute');res['claim_expired']=F(tB,dB,{'action':'admin-claim','code':exp})[0]
c=mkcode('1 hour')
res['claim_nonce_nodevice_hdr']=F(tB,'bad',{'action':'admin-claim','code':c})[0]
res['claim_ok']=F(tB,dB,{'action':'admin-claim','code':c})[0]
res['claim_replay_other']=F(tC,dC,{'action':'admin-claim','code':c})[0]
res['claim_replay_same']=F(tB,dB,{'action':'admin-claim','code':c})[0]
res['admin_flag']=F(tB,dB,{'action':'gallery'})[1].get('admin')
res['admin_otherdev_C_flag']=F(tC,dC,{'action':'gallery'})[1].get('admin')
res['admin_B_newdevice']=F(tB,dB2:=str(uuid.uuid4()),{'action':'gallery'})[1].get('admin')
res['C_still_denied']=F(tC,dC,{'action':'gallery-delete','id':gid})[0]
res['admin_update_200']=F(tB,dB,{'action':'gallery-update','id':gid,'description':'by admin'})[0]
res['owner_preserved']=q("select user_id::text=('%s') ok from mirsa_forge_gallery where id='%s'"%(uA,gid))[0]['ok']
res['admin_delete_200']=F(tB,dB,{'action':'gallery-delete','id':gid})[0]
res['gone']=q("select count(*) c from mirsa_forge_gallery where id='%s'"%gid)[0]['c']==0
# legacy unbound row
lid=str(uuid.uuid4())
q("insert into mirsa_forge_gallery(id,user_id,name,target_bundle_id,description,code,settings) values ('%s','%s','Legacy','com.x.y','',$$%s$$,'[]')"%(lid,uA,good))
res['legacy_author_404']=F(tA,dA,{'action':'gallery-update','id':lid,'name':'x'})[0]
res['legacy_admin_delete']=F(tB,dB,{'action':'gallery-delete','id':lid})[0]
# cleanup
for u in (uA,uB,uC):
    call(base+'/auth/v1/admin/users/'+u,None,{'apikey':SR,'Authorization':'Bearer '+SR},'DELETE')
q("delete from mirsa_forge_admins where user_id in ('%s','%s','%s')"%(uA,uB,uC));q("delete from mirsa_forge_admin_codes where used_device is not null or expires_at<now()");q("delete from mirsa_forge_gallery where name in ('GalTest','GalTest2','Legacy')")
print(json.dumps(res,indent=1))
