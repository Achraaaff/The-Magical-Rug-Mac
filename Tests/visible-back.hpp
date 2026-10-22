int visibleBack(const Cloth&c){
 int count=0;for(auto f:c.faces){V3 a=c.pos[f[0]],b=c.pos[f[1]],d=c.pos[f[2]];if(cross(b-a,d-a).z>=0)continue;V3 p=(a+b+d)*(1.f/3);bool visible=true;
 for(auto g:c.faces){V3 aa=c.pos[g[0]],u=c.pos[g[1]]-aa,v=c.pos[g[2]]-aa,w=p-aa;float det=u.x*v.y-u.y*v.x;if(std::abs(det)<1e-5f)continue;float s=(w.x*v.y-w.y*v.x)/det,t=(u.x*w.y-u.y*w.x)/det;if(s<0||t<0||s+t>1)continue;float z=aa.z+s*u.z+t*v.z;if(z>p.z+.1f){visible=false;break;}}
 count+=visible;}return count;
}
