import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import vm from "node:vm";
const source=readFileSync(new URL("../web/login.js",import.meta.url),"utf8");
function page(response){
  const fields={};
  for(const id of ["error","password","toggle-password","submit-login","form"]){
    fields[id]={dataset:{},listeners:{},attributes:{},type:"password",value:"fixture-password",addEventListener(name,callback){this.listeners[name]=callback;},setAttribute(name,value){this.attributes[name]=value;},removeAttribute(name){delete this.attributes[name];}};
  }
  fields.form.action="https://192.0.2.1/auth/login";
  let redirected=false;
  vm.runInNewContext(source,{
    document:{querySelector:()=>fields.form,getElementById:id=>fields[id]},
    location:{search:"",origin:"https://192.0.2.1",replace:()=>{redirected=true;}},
    URL,URLSearchParams,AbortSignal,
    FormData:class {constructor(){return [["username","admin"],["password","fixture-password"]];}},
    fetch:async(_url,options)=>{assert.equal(options.mode,"cors");assert.equal(options.credentials,"same-origin");return response;},
    setTimeout:callback=>callback(),
  });
  return {fields,redirected:()=>redirected,submit:()=>fields.form.listeners.submit({preventDefault(){}})};
}
const toggle=page({});
toggle.fields["toggle-password"].listeners.click();
assert.equal(toggle.fields.password.type,"text");
assert.equal(toggle.fields["toggle-password"].textContent,"Masquer");
toggle.fields["toggle-password"].listeners.click();
assert.equal(toggle.fields.password.type,"password");
for(const reason of ["invalid","wait"]){
  const p=page({ok:true,status:200,url:`https://192.0.2.1/login?error=${reason}`});
  await p.submit();
  assert.equal(p.fields.error.dataset.kind,"error");
  assert.equal(p.redirected(),false);
  assert.equal(p.fields["submit-login"].disabled,false);
}
const denied=page({ok:false,status:403});await denied.submit();
assert.match(denied.fields.error.textContent,/adresse|HTTPS/);
assert.equal(denied.redirected(),false);
const good=page({ok:true,status:200,url:"https://192.0.2.1/"});await good.submit();
assert.match(good.fields.error.textContent,/Mot de passe valide/);
assert.equal(good.fields.error.dataset.kind,"success");
assert.equal(good.fields.password.value,"");
assert.equal(good.redirected(),true);
console.log("Login visibility, validation feedback, rate limiting and origin error checks passed");
